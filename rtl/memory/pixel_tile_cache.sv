`timescale 1ns/1ps

// 32x4 RGBX8888 Tile Cache with 128 resident Tiles organized as 16 sets x
// 8 ways.  The skewed set index matches the software traffic model:
// set = tile_x - tile_y + (tile_x >> 2), modulo SET_COUNT.
module pixel_tile_cache #(
    parameter integer IMAGE_WIDTH = 1920,
    parameter integer IMAGE_HEIGHT = 1080,
    parameter integer TILE_W = 32,
    parameter integer TILE_H = 4,
    parameter integer SET_COUNT = 16,
    parameter integer WAYS = 8,
    parameter integer COORD_WIDTH = 12,
    parameter integer PIXEL_WIDTH = 32
) (
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         lookup_valid,
    output wire                         lookup_ready,
    input  wire [COORD_WIDTH-1:0]       lookup_x0,
    input  wire [COORD_WIDTH-1:0]       lookup_y0,

    output wire                         lookup_rsp_valid,
    input  wire                         lookup_rsp_ready,
    output wire [PIXEL_WIDTH-1:0]       pixel_p00,
    output wire [PIXEL_WIDTH-1:0]       pixel_p10,
    output wire [PIXEL_WIDTH-1:0]       pixel_p01,
    output wire [PIXEL_WIDTH-1:0]       pixel_p11,
    output wire                         cache_hit,
    output wire                         coord_valid,

    output wire                         fill_req_valid,
    input  wire                         fill_req_ready,
    output wire [COORD_WIDTH-1:0]       fill_tile_x,
    output wire [COORD_WIDTH-1:0]       fill_tile_y,
    output wire [1:0]                   fill_row_index,

    input  wire                         fill_data_valid,
    output wire                         fill_data_ready,
    input  wire [255:0]                 fill_data,
    input  wire [1:0]                   fill_data_row_index,
    input  wire [1:0]                   fill_data_beat_index
);
    localparam integer WAY_WIDTH = (WAYS <= 1) ? 1 : $clog2(WAYS);
    localparam integer BANK_PIXELS_PER_TILE = (TILE_W * TILE_H) / 4;
    localparam integer BANK_DEPTH = SET_COUNT * WAYS * BANK_PIXELS_PER_TILE;

    localparam [2:0] STATE_IDLE = 3'd0;
    localparam [2:0] STATE_CHECK = 3'd1;
    localparam [2:0] STATE_FILL_REQ = 3'd2;
    localparam [2:0] STATE_FILL_DATA = 3'd3;
    localparam [2:0] STATE_RESPONSE = 3'd4;

    reg [2:0] state;
    reg [COORD_WIDTH-1:0] lookup_x_reg;
    reg [COORD_WIDTH-1:0] lookup_y_reg;
    reg coord_valid_reg;

    reg [COORD_WIDTH-1:0] pending_tile_x;
    reg [COORD_WIDTH-1:0] pending_tile_y;
    reg [WAY_WIDTH-1:0] pending_way;
    reg [WAY_WIDTH-1:0] pending_set;
    reg [1:0] pending_row;

    reg valid_mem [0:SET_COUNT-1][0:WAYS-1];
    reg [COORD_WIDTH-1:0] tag_x_mem [0:SET_COUNT-1][0:WAYS-1];
    reg [COORD_WIDTH-1:0] tag_y_mem [0:SET_COUNT-1][0:WAYS-1];
    reg [WAY_WIDTH-1:0] lru_rank_mem [0:SET_COUNT-1][0:WAYS-1];

    reg [PIXEL_WIDTH-1:0] bank0_mem [0:BANK_DEPTH-1];
    reg [PIXEL_WIDTH-1:0] bank1_mem [0:BANK_DEPTH-1];
    reg [PIXEL_WIDTH-1:0] bank2_mem [0:BANK_DEPTH-1];
    reg [PIXEL_WIDTH-1:0] bank3_mem [0:BANK_DEPTH-1];

    reg [COORD_WIDTH-1:0] required_tile_x [0:3];
    reg [COORD_WIDTH-1:0] required_tile_y [0:3];
    reg required_hit [0:3];
    reg [WAY_WIDTH-1:0] required_way [0:3];
    reg all_required_hit;
    reg missing_found;
    reg [COORD_WIDTH-1:0] missing_tile_x;
    reg [COORD_WIDTH-1:0] missing_tile_y;
    integer missing_set;
    integer selected_way;
    integer set_cursor;
    integer way_cursor;
    integer tile_cursor;
    integer raw_set;
    integer set_for_tile;
    integer best_rank;
    reg invalid_way_found;

    reg [PIXEL_WIDTH-1:0] pixel_p00_comb;
    reg [PIXEL_WIDTH-1:0] pixel_p10_comb;
    reg [PIXEL_WIDTH-1:0] pixel_p01_comb;
    reg [PIXEL_WIDTH-1:0] pixel_p11_comb;

    function automatic integer tile_set_index(
        input integer tile_x,
        input integer tile_y
    );
        integer normalized;
        begin
            normalized = (tile_x - tile_y + (tile_x >> 2)) % SET_COUNT;
            if (normalized < 0)
                normalized = normalized + SET_COUNT;
            tile_set_index = normalized;
        end
    endfunction

    function automatic integer bank_word_index(
        input integer set_index_value,
        input integer way_index,
        input integer local_x,
        input integer local_y
    );
        begin
            bank_word_index =
                (set_index_value * WAYS + way_index) * BANK_PIXELS_PER_TILE
                + (local_y >> 1) * (TILE_W >> 1)
                + (local_x >> 1);
        end
    endfunction

    function automatic [PIXEL_WIDTH-1:0] read_pixel_word(
        input integer source_x,
        input integer source_y,
        input integer tile_x,
        input integer tile_y,
        input integer way_index
    );
        integer local_x;
        integer local_y;
        integer bank_index;
        integer word_index;
        begin
            local_x = source_x - tile_x * TILE_W;
            local_y = source_y - tile_y * TILE_H;
            bank_index = ((local_y & 1) << 1) | (local_x & 1);
            word_index = bank_word_index(
                tile_set_index(tile_x, tile_y), way_index, local_x, local_y
            );
            case (bank_index)
                0: read_pixel_word = bank0_mem[word_index];
                1: read_pixel_word = bank1_mem[word_index];
                2: read_pixel_word = bank2_mem[word_index];
                default: read_pixel_word = bank3_mem[word_index];
            endcase
        end
    endfunction

    // Identify the up to four Tiles needed by the 2x2 neighborhood and find
    // their current ways.  Duplicate Tile coordinates are harmless.
    always @* begin
        required_tile_x[0] = lookup_x_reg / TILE_W;
        required_tile_y[0] = lookup_y_reg / TILE_H;
        required_tile_x[1] = (lookup_x_reg + 1) / TILE_W;
        required_tile_y[1] = lookup_y_reg / TILE_H;
        required_tile_x[2] = lookup_x_reg / TILE_W;
        required_tile_y[2] = (lookup_y_reg + 1) / TILE_H;
        required_tile_x[3] = (lookup_x_reg + 1) / TILE_W;
        required_tile_y[3] = (lookup_y_reg + 1) / TILE_H;

        all_required_hit = 1'b1;
        missing_found = 1'b0;
        missing_tile_x = 0;
        missing_tile_y = 0;
        for (tile_cursor = 0; tile_cursor < 4; tile_cursor = tile_cursor + 1) begin
            required_hit[tile_cursor] = 1'b0;
            required_way[tile_cursor] = {WAY_WIDTH{1'b0}};
            set_for_tile = tile_set_index(
                required_tile_x[tile_cursor], required_tile_y[tile_cursor]
            );
            for (way_cursor = 0; way_cursor < WAYS; way_cursor = way_cursor + 1) begin
                if (valid_mem[set_for_tile][way_cursor]
                    && tag_x_mem[set_for_tile][way_cursor]
                         == required_tile_x[tile_cursor]
                    && tag_y_mem[set_for_tile][way_cursor]
                         == required_tile_y[tile_cursor]) begin
                    required_hit[tile_cursor] = 1'b1;
                    required_way[tile_cursor] = way_cursor;
                end
            end
            if (!required_hit[tile_cursor]) begin
                all_required_hit = 1'b0;
                if (!missing_found) begin
                    missing_found = 1'b1;
                    missing_tile_x = required_tile_x[tile_cursor];
                    missing_tile_y = required_tile_y[tile_cursor];
                end
            end
        end

        missing_set = tile_set_index(missing_tile_x, missing_tile_y);
        selected_way = 0;
        invalid_way_found = 1'b0;
        // Ranks are unsigned packed values; start at zero to avoid signed
        // comparison coercion turning an initial -1 into a large unsigned.
        best_rank = 0;
        for (way_cursor = 0; way_cursor < WAYS; way_cursor = way_cursor + 1) begin
            if (!valid_mem[missing_set][way_cursor] && !invalid_way_found) begin
                selected_way = way_cursor;
                invalid_way_found = 1'b1;
            end
            if (valid_mem[missing_set][way_cursor]
                && lru_rank_mem[missing_set][way_cursor] > best_rank) begin
                best_rank = lru_rank_mem[missing_set][way_cursor];
                if (invalid_way_found == 1'b0)
                    selected_way = way_cursor;
            end
        end

        pixel_p00_comb = {PIXEL_WIDTH{1'b0}};
        pixel_p10_comb = {PIXEL_WIDTH{1'b0}};
        pixel_p01_comb = {PIXEL_WIDTH{1'b0}};
        pixel_p11_comb = {PIXEL_WIDTH{1'b0}};
        if (coord_valid_reg && all_required_hit) begin
            pixel_p00_comb = read_pixel_word(
                lookup_x_reg, lookup_y_reg,
                required_tile_x[0], required_tile_y[0], required_way[0]
            );
            pixel_p10_comb = read_pixel_word(
                lookup_x_reg + 1, lookup_y_reg,
                required_tile_x[1], required_tile_y[1], required_way[1]
            );
            pixel_p01_comb = read_pixel_word(
                lookup_x_reg, lookup_y_reg + 1,
                required_tile_x[2], required_tile_y[2], required_way[2]
            );
            pixel_p11_comb = read_pixel_word(
                lookup_x_reg + 1, lookup_y_reg + 1,
                required_tile_x[3], required_tile_y[3], required_way[3]
            );
        end
    end

    task automatic touch_lru(input integer set_index_value, input integer way_index);
        integer old_rank;
        integer touch_way_cursor;
        begin
            old_rank = lru_rank_mem[set_index_value][way_index];
            for (touch_way_cursor = 0; touch_way_cursor < WAYS; touch_way_cursor = touch_way_cursor + 1) begin
                if (touch_way_cursor == way_index)
                    lru_rank_mem[set_index_value][touch_way_cursor] <= 0;
                else if (lru_rank_mem[set_index_value][touch_way_cursor] < old_rank)
                    lru_rank_mem[set_index_value][touch_way_cursor]
                        <= lru_rank_mem[set_index_value][touch_way_cursor] + 1'b1;
            end
        end
    endtask

    assign lookup_ready = (state == STATE_IDLE) && rst_n;
    assign lookup_rsp_valid = (state == STATE_RESPONSE);
    assign pixel_p00 = pixel_p00_comb;
    assign pixel_p10 = pixel_p10_comb;
    assign pixel_p01 = pixel_p01_comb;
    assign pixel_p11 = pixel_p11_comb;
    assign cache_hit = lookup_rsp_valid && coord_valid_reg;
    assign coord_valid = coord_valid_reg;

    assign fill_req_valid = (state == STATE_FILL_REQ);
    assign fill_tile_x = pending_tile_x;
    assign fill_tile_y = pending_tile_y;
    assign fill_row_index = pending_row;
    assign fill_data_ready = (state == STATE_FILL_DATA);

    integer lane;
    integer local_x_write;
    integer local_y_write;
    integer bank_write;
    integer word_index_write;
    integer reset_set;
    integer reset_way;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            lookup_x_reg <= 0;
            lookup_y_reg <= 0;
            coord_valid_reg <= 1'b0;
            pending_tile_x <= 0;
            pending_tile_y <= 0;
            pending_way <= 0;
            pending_set <= 0;
            pending_row <= 0;
            for (reset_set = 0; reset_set < SET_COUNT; reset_set = reset_set + 1) begin
                for (reset_way = 0; reset_way < WAYS; reset_way = reset_way + 1) begin
                    valid_mem[reset_set][reset_way] <= 1'b0;
                    tag_x_mem[reset_set][reset_way] <= 0;
                    tag_y_mem[reset_set][reset_way] <= 0;
                    lru_rank_mem[reset_set][reset_way] <= reset_way;
                end
            end
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (lookup_valid && lookup_ready) begin
                        lookup_x_reg <= lookup_x0;
                        lookup_y_reg <= lookup_y0;
                        coord_valid_reg <= 1'b0;
                        state <= STATE_CHECK;
                    end
                end

                STATE_CHECK: begin
                    if ((lookup_x_reg >= IMAGE_WIDTH - 1)
                        || (lookup_y_reg >= IMAGE_HEIGHT - 1)) begin
                        coord_valid_reg <= 1'b0;
                        state <= STATE_RESPONSE;
                    end else if (all_required_hit) begin
                        coord_valid_reg <= 1'b1;
                        for (tile_cursor = 0; tile_cursor < 4; tile_cursor = tile_cursor + 1)
                            if (required_hit[tile_cursor])
                                touch_lru(
                                    tile_set_index(
                                        required_tile_x[tile_cursor],
                                        required_tile_y[tile_cursor]
                                    ),
                                    required_way[tile_cursor]
                                );
                        state <= STATE_RESPONSE;
                    end else begin
                        pending_tile_x <= missing_tile_x;
                        pending_tile_y <= missing_tile_y;
                        pending_set <= missing_set;
                        pending_way <= selected_way;
                        pending_row <= 2'd0;
                        state <= STATE_FILL_REQ;
                    end
                end

                STATE_FILL_REQ: begin
                    if (fill_req_valid && fill_req_ready)
                        state <= STATE_FILL_DATA;
                end

                STATE_FILL_DATA: begin
                    if (fill_data_valid && fill_data_ready) begin
                        for (lane = 0; lane < 8; lane = lane + 1) begin
                            local_x_write = fill_data_beat_index * 8 + lane;
                            local_y_write = fill_data_row_index;
                            bank_write = ((local_y_write & 1) << 1)
                                         | (local_x_write & 1);
                            word_index_write = bank_word_index(
                                pending_set, pending_way,
                                local_x_write, local_y_write
                            );
                            case (bank_write)
                                0: bank0_mem[word_index_write]
                                    <= fill_data[lane*32 +: 32];
                                1: bank1_mem[word_index_write]
                                    <= fill_data[lane*32 +: 32];
                                2: bank2_mem[word_index_write]
                                    <= fill_data[lane*32 +: 32];
                                default: bank3_mem[word_index_write]
                                    <= fill_data[lane*32 +: 32];
                            endcase
                        end

                        if (fill_data_beat_index == 2'd3) begin
                            if (pending_row == TILE_H - 1) begin
                                valid_mem[pending_set][pending_way] <= 1'b1;
                                tag_x_mem[pending_set][pending_way] <= pending_tile_x;
                                tag_y_mem[pending_set][pending_way] <= pending_tile_y;
                                touch_lru(pending_set, pending_way);
                                state <= STATE_CHECK;
                            end else begin
                                pending_row <= pending_row + 1'b1;
                                state <= STATE_FILL_REQ;
                            end
                        end
                    end
                end

                STATE_RESPONSE: begin
                    if (lookup_rsp_valid && lookup_rsp_ready)
                        state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule

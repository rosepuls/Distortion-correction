`timescale 1ns/1ps

// Eight-way tree pseudo-LRU state.
// state[0] is the root, state[1:2] are the second level and
// state[3:6] select the older entry in each pair. A zero bit selects
// the left/older branch and a one bit selects the right/older branch.
module pixel_tile_cache_plru8 (
    input  wire [6:0] state,
    input  wire [2:0] touch_way,
    output reg  [6:0] next_state,
    output reg  [2:0] victim_way
);
    always @* begin
        next_state = state;
        case (touch_way)
            3'd0: begin next_state[0] = 1'b1; next_state[1] = 1'b1; next_state[3] = 1'b1; end
            3'd1: begin next_state[0] = 1'b1; next_state[1] = 1'b1; next_state[3] = 1'b0; end
            3'd2: begin next_state[0] = 1'b1; next_state[1] = 1'b0; next_state[4] = 1'b1; end
            3'd3: begin next_state[0] = 1'b1; next_state[1] = 1'b0; next_state[4] = 1'b0; end
            3'd4: begin next_state[0] = 1'b0; next_state[2] = 1'b1; next_state[5] = 1'b1; end
            3'd5: begin next_state[0] = 1'b0; next_state[2] = 1'b1; next_state[5] = 1'b0; end
            3'd6: begin next_state[0] = 1'b0; next_state[2] = 1'b0; next_state[6] = 1'b1; end
            3'd7: begin next_state[0] = 1'b0; next_state[2] = 1'b0; next_state[6] = 1'b0; end
            default: next_state = state;
        endcase

        victim_way[2] = state[0];
        if (state[0] == 1'b0) begin
            victim_way[1] = state[1];
            if (state[1] == 1'b0)
                victim_way[0] = state[3];
            else
                victim_way[0] = state[4];
        end else begin
            victim_way[1] = state[2];
            if (state[2] == 1'b0)
                victim_way[0] = state[5];
            else
                victim_way[0] = state[6];
        end
    end
endmodule

// 32x4 RGBX8888 Tile Cache.
// Four synchronous 128-bit banks serve one 2x2 neighborhood in parallel.
module pixel_tile_cache #(
    parameter integer IMAGE_WIDTH = 1920,
    parameter integer IMAGE_HEIGHT = 1080,
    parameter integer TILE_W = 32,
    parameter integer TILE_H = 4,
    parameter integer SET_COUNT = 16,
    parameter integer WAYS = 8,
    parameter integer COORD_WIDTH = 12,
    parameter integer PIXEL_WIDTH = 32,
    parameter integer BANK_READ_LATENCY = 1,
    parameter integer USE_PSEUDO_LRU = 0
) (
    input  wire                         clk,
    input  wire                         rst_n,
    // Pulse once at the beginning of a new source frame.  Tags/data stay in
    // BRAM, but all valid bits are retired before lookups are accepted again.
    input  wire                         invalidate,
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
    localparam integer SET_WIDTH = (SET_COUNT <= 1) ? 1 : $clog2(SET_COUNT);
    localparam integer BANK_WORDS_PER_TILE = (TILE_W * TILE_H / 4) / 4;
    localparam integer BANK_WORD_COUNT = SET_COUNT * WAYS * BANK_WORDS_PER_TILE;
    localparam integer BANK_ADDR_WIDTH = (BANK_WORD_COUNT <= 2)
                                         ? 1 : $clog2(BANK_WORD_COUNT);
    localparam integer BANK_READ_STAGES = (BANK_READ_LATENCY < 1) ? 1 : BANK_READ_LATENCY;
    localparam integer RESPONSE_FIFO_DEPTH = BANK_READ_STAGES + 2;
    localparam integer FIFO_PTR_WIDTH = (RESPONSE_FIFO_DEPTH <= 2)
                                        ? 1 : $clog2(RESPONSE_FIFO_DEPTH);

    localparam [1:0] FILL_IDLE = 2'd0;
    localparam [1:0] FILL_REQ = 2'd1;
    localparam [1:0] FILL_DATA = 2'd2;
    localparam [1:0] PIPE_EMPTY = 2'd0;
    localparam [1:0] PIPE_HIT = 2'd1;
    localparam [1:0] PIPE_BLACK = 2'd2;

    reg [1:0] fill_state;
    reg [COORD_WIDTH-1:0] pending_tile_x;
    reg [COORD_WIDTH-1:0] pending_tile_y;
    reg [WAY_WIDTH-1:0] pending_way;
    reg [SET_WIDTH-1:0] pending_set;
    reg [1:0] pending_row;
    reg miss_retry_valid;
    reg [COORD_WIDTH-1:0] miss_retry_x;
    reg [COORD_WIDTH-1:0] miss_retry_y;
    reg invalidate_active;
    reg [SET_WIDTH-1:0] invalidate_set;

    // Four independent tag probes are required for each 2x2 neighborhood.
    // Leaving these shallow arrays unconstrained makes PDS replicate them as
    // multi-port distributed RAM (and then route a large LUTRAM/MUX fabric).
    // The entire metadata store is only 64 entries in the production cache,
    // so registers are both smaller in routing cost and permit the four
    // combinational reads without RAM-port replication.
    reg valid_mem [0:SET_COUNT-1][0:WAYS-1]
        /* synthesis syn_ramstyle = "registers" */;
    reg [COORD_WIDTH-1:0] tag_x_mem [0:SET_COUNT-1][0:WAYS-1]
        /* synthesis syn_ramstyle = "registers" */;
    reg [COORD_WIDTH-1:0] tag_y_mem [0:SET_COUNT-1][0:WAYS-1]
        /* synthesis syn_ramstyle = "registers" */;
    reg [WAY_WIDTH-1:0] lru_rank_mem [0:SET_COUNT-1][0:WAYS-1]
        /* synthesis syn_ramstyle = "registers" */;
    localparam integer PLRU_BITS = (WAYS == 8) ? 7 : (WAYS == 4) ? 3 : 1;
    // The tree PLRU implementation below exists only for four- and eight-way
    // sets.  Two-way (and direct-mapped) configurations must use the compact
    // conventional LRU path; otherwise a 2-way build would keep selecting a
    // stale fixed victim because plru_touch_state intentionally has no 2-way
    // branch.
    localparam integer USE_TREE_PLRU = (USE_PSEUDO_LRU != 0)
                                    && ((WAYS == 4) || (WAYS == 8));
    reg [PLRU_BITS-1:0] plru_state_mem [0:SET_COUNT-1]
        /* synthesis syn_ramstyle = "registers" */;

    reg [COORD_WIDTH-1:0] req_x [0:3];
    reg [COORD_WIDTH-1:0] req_y [0:3];
    reg [COORD_WIDTH-1:0] req_tile_x [0:3];
    reg [COORD_WIDTH-1:0] req_tile_y [0:3];
    integer req_set [0:3];
    integer req_local_x [0:3];
    integer req_local_y [0:3];
    reg req_hit [0:3];
    reg [WAY_WIDTH-1:0] req_way [0:3];
    reg [1:0] req_bank [0:3];
    reg [1:0] req_slot [0:3];
    reg req_coord_valid;
    reg req_all_hit;
    reg [COORD_WIDTH-1:0] missing_tile_x_comb;
    reg [COORD_WIDTH-1:0] missing_tile_y_comb;
    integer missing_set_comb;
    integer selected_way_comb;
    reg selected_invalid_comb;
    integer best_rank_comb;
    integer tag_i;
    integer tag_way_i;
    wire [COORD_WIDTH-1:0] decode_x = miss_retry_valid ? miss_retry_x : lookup_x0;
    wire [COORD_WIDTH-1:0] decode_y = miss_retry_valid ? miss_retry_y : lookup_y0;

    function automatic integer tile_set_index(input integer tile_x, input integer tile_y);
        begin
            // SET_COUNT is constrained to a power of two.  The low bits are
            // the exact modulo result for both positive and negative
            // two's-complement skew values, with no divider or bmsSMOD.
            tile_set_index = (tile_x - tile_y + (tile_x >> 2)) & (SET_COUNT - 1);
        end
    endfunction

    function automatic integer bank_word_index(
        input integer set_index_value,
        input integer way_index,
        input integer local_x,
        input integer local_y
    );
        begin
            if ((SET_COUNT == 32) && (TILE_W == 32) && (TILE_H == 4)
                && (WAYS == 8))
                bank_word_index = (set_index_value << 6)
                                  + (way_index << 3)
                                  + ((local_y >> 1) << 2)
                                  + (local_x >> 3);
            else
                bank_word_index = (set_index_value * WAYS + way_index)
                                  * BANK_WORDS_PER_TILE
                                  + (local_y >> 1) * (TILE_W >> 3)
                                  + (local_x >> 3);
        end
    endfunction

    function automatic [PIXEL_WIDTH-1:0] word_pixel(
        input [127:0] word,
        input [1:0] slot
    );
        begin
            word_pixel = word[slot*PIXEL_WIDTH +: PIXEL_WIDTH];
        end
    endfunction

    function automatic [PLRU_BITS-1:0] plru_touch_state(
        input [PLRU_BITS-1:0] state_value,
        input integer way_index
    );
        begin
            plru_touch_state = state_value;
            if (WAYS == 4) begin
                case (way_index)
                    0: begin plru_touch_state[0] = 1'b1; plru_touch_state[1] = 1'b1; end
                    1: begin plru_touch_state[0] = 1'b1; plru_touch_state[1] = 1'b0; end
                    2: begin plru_touch_state[0] = 1'b0; plru_touch_state[2] = 1'b1; end
                    3: begin plru_touch_state[0] = 1'b0; plru_touch_state[2] = 1'b0; end
                    default: plru_touch_state = state_value;
                endcase
            end else if (WAYS == 8) begin
                case (way_index)
                    0: begin plru_touch_state[0] = 1'b1; plru_touch_state[1] = 1'b1; plru_touch_state[3] = 1'b1; end
                    1: begin plru_touch_state[0] = 1'b1; plru_touch_state[1] = 1'b1; plru_touch_state[3] = 1'b0; end
                    2: begin plru_touch_state[0] = 1'b1; plru_touch_state[1] = 1'b0; plru_touch_state[4] = 1'b1; end
                    3: begin plru_touch_state[0] = 1'b1; plru_touch_state[1] = 1'b0; plru_touch_state[4] = 1'b0; end
                    4: begin plru_touch_state[0] = 1'b0; plru_touch_state[2] = 1'b1; plru_touch_state[5] = 1'b1; end
                    5: begin plru_touch_state[0] = 1'b0; plru_touch_state[2] = 1'b1; plru_touch_state[5] = 1'b0; end
                    6: begin plru_touch_state[0] = 1'b0; plru_touch_state[2] = 1'b0; plru_touch_state[6] = 1'b1; end
                    7: begin plru_touch_state[0] = 1'b0; plru_touch_state[2] = 1'b0; plru_touch_state[6] = 1'b0; end
                    default: plru_touch_state = state_value;
                endcase
            end
        end
    endfunction

    function automatic integer plru_victim_index(
        input [PLRU_BITS-1:0] state_value
    );
        reg [2:0] victim_value;
        begin
            victim_value = 3'd0;
            if (WAYS == 4) begin
                victim_value[1] = state_value[0];
                if (state_value[0] == 1'b0)
                    victim_value[0] = state_value[1];
                else
                    victim_value[0] = state_value[2];
            end else if (WAYS == 8) begin
                victim_value[2] = state_value[0];
                if (state_value[0] == 1'b0) begin
                    victim_value[1] = state_value[1];
                    if (state_value[1] == 1'b0)
                        victim_value[0] = state_value[3];
                    else
                        victim_value[0] = state_value[4];
                end else begin
                    victim_value[1] = state_value[2];
                    if (state_value[2] == 1'b0)
                        victim_value[0] = state_value[5];
                    else
                        victim_value[0] = state_value[6];
                end
            end else begin
                victim_value = 3'd0;
            end
            plru_victim_index = victim_value;
        end
    endfunction

    // Tag lookup and fixed Tile/local-coordinate arithmetic.
    always @* begin
        req_x[0] = decode_x;
        req_y[0] = decode_y;
        req_x[1] = decode_x + 1'b1;
        req_y[1] = decode_y;
        req_x[2] = decode_x;
        req_y[2] = decode_y + 1'b1;
        req_x[3] = decode_x + 1'b1;
        req_y[3] = decode_y + 1'b1;
        req_coord_valid = (decode_x < IMAGE_WIDTH - 1)
                          && (decode_y < IMAGE_HEIGHT - 1);
        req_all_hit = 1'b1;
        missing_tile_x_comb = 0;
        missing_tile_y_comb = 0;
        missing_set_comb = 0;
        selected_way_comb = 0;
        selected_invalid_comb = 1'b0;

        for (tag_i = 0; tag_i < 4; tag_i = tag_i + 1) begin
            req_tile_x[tag_i] = req_x[tag_i] >> 5;
            req_tile_y[tag_i] = req_y[tag_i] >> 2;
            req_local_x[tag_i] = req_x[tag_i] & 31;
            req_local_y[tag_i] = req_y[tag_i] & 3;
            req_set[tag_i] = tile_set_index(req_tile_x[tag_i], req_tile_y[tag_i]);
            req_bank[tag_i] = ((req_local_y[tag_i] & 1) << 1)
                              | (req_local_x[tag_i] & 1);
            req_slot[tag_i] = (req_local_x[tag_i] >> 1) & 3;
            req_hit[tag_i] = 1'b0;
            req_way[tag_i] = {WAY_WIDTH{1'b0}};
            for (tag_way_i = 0; tag_way_i < WAYS; tag_way_i = tag_way_i + 1)
                if (valid_mem[req_set[tag_i]][tag_way_i]
                    && tag_x_mem[req_set[tag_i]][tag_way_i] == req_tile_x[tag_i]
                    && tag_y_mem[req_set[tag_i]][tag_way_i] == req_tile_y[tag_i]) begin
                    req_hit[tag_i] = 1'b1;
                    req_way[tag_i] = tag_way_i;
                end
            if (!req_hit[tag_i]) begin
                req_all_hit = 1'b0;
                if (missing_tile_x_comb == 0 && missing_tile_y_comb == 0) begin
                    missing_tile_x_comb = req_tile_x[tag_i];
                    missing_tile_y_comb = req_tile_y[tag_i];
                    missing_set_comb = req_set[tag_i];
                end
            end
        end

        if (req_coord_valid) begin
            missing_set_comb = tile_set_index(missing_tile_x_comb,
                                              missing_tile_y_comb);
            for (tag_way_i = 0; tag_way_i < WAYS; tag_way_i = tag_way_i + 1) begin
                if (!valid_mem[missing_set_comb][tag_way_i]
                    && !selected_invalid_comb) begin
                    selected_way_comb = tag_way_i;
                    selected_invalid_comb = 1'b1;
                end
            end
            if (!selected_invalid_comb) begin
                if (USE_TREE_PLRU != 0) begin
                    selected_way_comb = plru_victim_index(plru_state_mem[missing_set_comb]);
                end else begin
                    selected_way_comb = 0;
                    best_rank_comb = 0;
                    for (tag_way_i = 0; tag_way_i < WAYS; tag_way_i = tag_way_i + 1)
                        if (valid_mem[missing_set_comb][tag_way_i]
                            && (lru_rank_mem[missing_set_comb][tag_way_i] >= best_rank_comb)) begin
                            best_rank_comb = lru_rank_mem[missing_set_comb][tag_way_i];
                            selected_way_comb = tag_way_i;
                        end
                end
            end
        end
    end

    wire request_hit = req_coord_valid && req_all_hit;
    wire request_black = !req_coord_valid;
    wire request_miss = req_coord_valid && !req_all_hit;

    // Hit/black response pipeline.  The pipeline token and the synchronous
    // bank output have identical latency, so no per-hit bubble is introduced.
    reg [1:0] pipe_kind [0:BANK_READ_STAGES-1];
    reg [1:0] pipe_bank [0:BANK_READ_STAGES-1][0:3];
    reg [1:0] pipe_slot [0:BANK_READ_STAGES-1][0:3];
    integer pipe_valid_count;
    integer pipe_i;
    always @* begin
        pipe_valid_count = 0;
        for (pipe_i = 0; pipe_i < BANK_READ_STAGES; pipe_i = pipe_i + 1)
            if (pipe_kind[pipe_i] != PIPE_EMPTY)
                pipe_valid_count = pipe_valid_count + 1;
    end

    integer fifo_count;
    reg [FIFO_PTR_WIDTH-1:0] fifo_wr_ptr;
    reg [FIFO_PTR_WIDTH-1:0] fifo_rd_ptr;
    reg [PIXEL_WIDTH-1:0] fifo_p00 [0:RESPONSE_FIFO_DEPTH-1];
    reg [PIXEL_WIDTH-1:0] fifo_p10 [0:RESPONSE_FIFO_DEPTH-1];
    reg [PIXEL_WIDTH-1:0] fifo_p01 [0:RESPONSE_FIFO_DEPTH-1];
    reg [PIXEL_WIDTH-1:0] fifo_p11 [0:RESPONSE_FIFO_DEPTH-1];
    reg fifo_coord [0:RESPONSE_FIFO_DEPTH-1];

    assign lookup_rsp_valid = (fifo_count != 0);
    assign pixel_p00 = (fifo_count != 0) ? fifo_p00[fifo_rd_ptr] : {PIXEL_WIDTH{1'b0}};
    assign pixel_p10 = (fifo_count != 0) ? fifo_p10[fifo_rd_ptr] : {PIXEL_WIDTH{1'b0}};
    assign pixel_p01 = (fifo_count != 0) ? fifo_p01[fifo_rd_ptr] : {PIXEL_WIDTH{1'b0}};
    assign pixel_p11 = (fifo_count != 0) ? fifo_p11[fifo_rd_ptr] : {PIXEL_WIDTH{1'b0}};
    assign coord_valid = (fifo_count != 0) && fifo_coord[fifo_rd_ptr];
    assign cache_hit = coord_valid;

    wire lookup_capacity = (fifo_count + pipe_valid_count < RESPONSE_FIFO_DEPTH);
    assign lookup_ready = rst_n && !invalidate && !invalidate_active && !miss_retry_valid
                          && (fill_state == FILL_IDLE) && lookup_capacity;
    wire external_lookup_fire = lookup_valid && lookup_ready;
    wire retry_fire = rst_n && !invalidate && !invalidate_active && miss_retry_valid
                      && (fill_state == FILL_IDLE) && lookup_capacity;
    wire lookup_fire = external_lookup_fire || retry_fire;
    wire bank_read_en = lookup_fire && request_hit;

    reg [BANK_ADDR_WIDTH-1:0] bank_rd_addr_comb [0:3];
    integer bank_addr_i;
    always @* begin
        for (bank_addr_i = 0; bank_addr_i < 4; bank_addr_i = bank_addr_i + 1)
            bank_rd_addr_comb[bank_addr_i] = {BANK_ADDR_WIDTH{1'b0}};
        if (request_hit)
            for (bank_addr_i = 0; bank_addr_i < 4; bank_addr_i = bank_addr_i + 1)
                bank_rd_addr_comb[req_bank[bank_addr_i]] = bank_word_index(
                    req_set[bank_addr_i], req_way[bank_addr_i],
                    req_local_x[bank_addr_i], req_local_y[bank_addr_i]
                );
    end

    wire [127:0] bank0_rd_data;
    wire [127:0] bank1_rd_data;
    wire [127:0] bank2_rd_data;
    wire [127:0] bank3_rd_data;
    wire bank0_rd_valid;
    wire bank1_rd_valid;
    wire bank2_rd_valid;
    wire bank3_rd_valid;

    reg [127:0] fill_bank_data [0:3];
    integer fill_lane_i;
    integer fill_bank_i;
    integer fill_slot_i;
    always @* begin
        for (fill_bank_i = 0; fill_bank_i < 4; fill_bank_i = fill_bank_i + 1)
            fill_bank_data[fill_bank_i] = 128'd0;
        for (fill_lane_i = 0; fill_lane_i < 8; fill_lane_i = fill_lane_i + 1) begin
            fill_bank_i = ((fill_data_row_index & 1) << 1)
                          | (fill_lane_i & 1);
            fill_slot_i = (fill_lane_i >> 1) & 3;
            fill_bank_data[fill_bank_i][fill_slot_i*PIXEL_WIDTH +: PIXEL_WIDTH]
                = fill_data[fill_lane_i*PIXEL_WIDTH +: PIXEL_WIDTH];
        end
    end

    wire [BANK_ADDR_WIDTH-1:0] bank_wr_addr = bank_word_index(
        pending_set, pending_way, fill_data_beat_index * 8, fill_data_row_index
    );
    wire fill_write_fire = (fill_state == FILL_DATA) && fill_data_valid;
    wire bank0_wr_en = fill_write_fire && !fill_data_row_index[0];
    wire bank1_wr_en = fill_write_fire && !fill_data_row_index[0];
    wire bank2_wr_en = fill_write_fire && fill_data_row_index[0];
    wire bank3_wr_en = fill_write_fire && fill_data_row_index[0];

    // These instance names are intentionally stable for structural checks.
    tile_cache_bank_ram #(.BANK_READ_LATENCY(BANK_READ_LATENCY),
                          .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH)) bank0_ram (
        .clk(clk), .rst_n(rst_n), .wr_en(bank0_wr_en), .wr_addr(bank_wr_addr),
        .wr_data(fill_bank_data[0]), .rd_en(bank_read_en),
        .rd_addr(bank_rd_addr_comb[0]), .rd_data(bank0_rd_data),
        .rd_valid(bank0_rd_valid)
    );
    tile_cache_bank_ram #(.BANK_READ_LATENCY(BANK_READ_LATENCY),
                          .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH)) bank1_ram (
        .clk(clk), .rst_n(rst_n), .wr_en(bank1_wr_en), .wr_addr(bank_wr_addr),
        .wr_data(fill_bank_data[1]), .rd_en(bank_read_en),
        .rd_addr(bank_rd_addr_comb[1]), .rd_data(bank1_rd_data),
        .rd_valid(bank1_rd_valid)
    );
    tile_cache_bank_ram #(.BANK_READ_LATENCY(BANK_READ_LATENCY),
                          .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH)) bank2_ram (
        .clk(clk), .rst_n(rst_n), .wr_en(bank2_wr_en), .wr_addr(bank_wr_addr),
        .wr_data(fill_bank_data[2]), .rd_en(bank_read_en),
        .rd_addr(bank_rd_addr_comb[2]), .rd_data(bank2_rd_data),
        .rd_valid(bank2_rd_valid)
    );
    tile_cache_bank_ram #(.BANK_READ_LATENCY(BANK_READ_LATENCY),
                          .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH)) bank3_ram (
        .clk(clk), .rst_n(rst_n), .wr_en(bank3_wr_en), .wr_addr(bank_wr_addr),
        .wr_data(fill_bank_data[3]), .rd_en(bank_read_en),
        .rd_addr(bank_rd_addr_comb[3]), .rd_data(bank3_rd_data),
        .rd_valid(bank3_rd_valid)
    );

    assign fill_req_valid = (fill_state == FILL_REQ)
                            && !invalidate && !invalidate_active;
    assign fill_tile_x = pending_tile_x;
    assign fill_tile_y = pending_tile_y;
    assign fill_row_index = pending_row;
    assign fill_data_ready = (fill_state == FILL_DATA)
                             && !invalidate && !invalidate_active;

    wire bank_rsp_valid = bank0_rd_valid && bank1_rd_valid
                          && bank2_rd_valid && bank3_rd_valid;
    wire response_push = (pipe_kind[BANK_READ_STAGES-1] == PIPE_BLACK)
                         || ((pipe_kind[BANK_READ_STAGES-1] == PIPE_HIT)
                             && bank_rsp_valid);
    wire response_pop = lookup_rsp_valid && lookup_rsp_ready;

    task automatic touch_lru(input integer set_index_value, input integer way_index);
        integer old_rank;
        integer touch_way_i;
        begin
            old_rank = lru_rank_mem[set_index_value][way_index];
            for (touch_way_i = 0; touch_way_i < WAYS; touch_way_i = touch_way_i + 1) begin
                if (touch_way_i == way_index)
                    lru_rank_mem[set_index_value][touch_way_i] <= 0;
                else if (valid_mem[set_index_value][touch_way_i]
                         && lru_rank_mem[set_index_value][touch_way_i] < old_rank)
                    lru_rank_mem[set_index_value][touch_way_i]
                        <= lru_rank_mem[set_index_value][touch_way_i] + 1'b1;
            end
        end
    endtask

    integer reset_set_i;
    integer reset_way_i;
    integer reset_pipe_i;
    integer reset_bank_i;
    integer shift_pipe_i;
    integer write_fifo_ptr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fill_state <= FILL_IDLE;
            pending_tile_x <= 0;
            pending_tile_y <= 0;
            pending_way <= 0;
            pending_set <= 0;
            pending_row <= 0;
            miss_retry_valid <= 1'b0;
            miss_retry_x <= 0;
            miss_retry_y <= 0;
            invalidate_active <= 1'b0;
            invalidate_set <= 0;
            fifo_count <= 0;
            fifo_wr_ptr <= 0;
            fifo_rd_ptr <= 0;
            for (reset_set_i = 0; reset_set_i < SET_COUNT; reset_set_i = reset_set_i + 1) begin
                for (reset_way_i = 0; reset_way_i < WAYS; reset_way_i = reset_way_i + 1) begin
                    valid_mem[reset_set_i][reset_way_i] <= 1'b0;
                    lru_rank_mem[reset_set_i][reset_way_i] <= reset_way_i;
                end
                plru_state_mem[reset_set_i] <= {PLRU_BITS{1'b0}};
            end
            for (reset_pipe_i = 0; reset_pipe_i < BANK_READ_STAGES; reset_pipe_i = reset_pipe_i + 1) begin
                pipe_kind[reset_pipe_i] <= PIPE_EMPTY;
            end
            // fifo_count=0 and PIPE_EMPTY make payload entries unreachable.
            // Keep response pixels and bank/slot payloads out of the reset
            // tree; only their validity/state requires initialization.
        end else begin
            // A frame boundary invalidates tags a set at a time.  This keeps
            // the operation bounded and avoids a large reset fanout while
            // guaranteeing that no tile from the previous frame can hit.
            if (invalidate_active) begin
                for (reset_way_i = 0; reset_way_i < WAYS; reset_way_i = reset_way_i + 1)
                    valid_mem[invalidate_set][reset_way_i] <= 1'b0;
                if (invalidate_set == SET_COUNT - 1) begin
                    invalidate_active <= 1'b0;
                    invalidate_set <= 0;
                end else begin
                    invalidate_set <= invalidate_set + 1'b1;
                end
            end else if (invalidate && (fill_state == FILL_IDLE)
                         && !miss_retry_valid) begin
                invalidate_active <= 1'b1;
                invalidate_set <= 0;
            end

            for (shift_pipe_i = BANK_READ_STAGES-1;
                 shift_pipe_i > 0;
                 shift_pipe_i = shift_pipe_i - 1) begin
                pipe_kind[shift_pipe_i] <= pipe_kind[shift_pipe_i-1];
                for (reset_bank_i = 0; reset_bank_i < 4; reset_bank_i = reset_bank_i + 1) begin
                    pipe_bank[shift_pipe_i][reset_bank_i]
                        <= pipe_bank[shift_pipe_i-1][reset_bank_i];
                    pipe_slot[shift_pipe_i][reset_bank_i]
                        <= pipe_slot[shift_pipe_i-1][reset_bank_i];
                end
            end
            pipe_kind[0] <= PIPE_EMPTY;
            if (lookup_fire) begin
                if (request_black)
                    pipe_kind[0] <= PIPE_BLACK;
                else if (request_hit) begin
                    pipe_kind[0] <= PIPE_HIT;
                    for (reset_bank_i = 0; reset_bank_i < 4; reset_bank_i = reset_bank_i + 1) begin
                        pipe_bank[0][reset_bank_i] <= req_bank[reset_bank_i];
                        pipe_slot[0][reset_bank_i] <= req_slot[reset_bank_i];
                    end
                end
            end

            if (response_push) begin
                write_fifo_ptr = fifo_wr_ptr;
                if (pipe_kind[BANK_READ_STAGES-1] == PIPE_BLACK) begin
                    fifo_p00[write_fifo_ptr] <= 0;
                    fifo_p10[write_fifo_ptr] <= 0;
                    fifo_p01[write_fifo_ptr] <= 0;
                    fifo_p11[write_fifo_ptr] <= 0;
                    fifo_coord[write_fifo_ptr] <= 1'b0;
                end else begin
                    fifo_p00[write_fifo_ptr] <= word_pixel(
                        (pipe_bank[BANK_READ_STAGES-1][0] == 0) ? bank0_rd_data
                        : (pipe_bank[BANK_READ_STAGES-1][0] == 1) ? bank1_rd_data
                        : (pipe_bank[BANK_READ_STAGES-1][0] == 2) ? bank2_rd_data
                        : bank3_rd_data,
                        pipe_slot[BANK_READ_STAGES-1][0]
                    );
                    fifo_p10[write_fifo_ptr] <= word_pixel(
                        (pipe_bank[BANK_READ_STAGES-1][1] == 0) ? bank0_rd_data
                        : (pipe_bank[BANK_READ_STAGES-1][1] == 1) ? bank1_rd_data
                        : (pipe_bank[BANK_READ_STAGES-1][1] == 2) ? bank2_rd_data
                        : bank3_rd_data,
                        pipe_slot[BANK_READ_STAGES-1][1]
                    );
                    fifo_p01[write_fifo_ptr] <= word_pixel(
                        (pipe_bank[BANK_READ_STAGES-1][2] == 0) ? bank0_rd_data
                        : (pipe_bank[BANK_READ_STAGES-1][2] == 1) ? bank1_rd_data
                        : (pipe_bank[BANK_READ_STAGES-1][2] == 2) ? bank2_rd_data
                        : bank3_rd_data,
                        pipe_slot[BANK_READ_STAGES-1][2]
                    );
                    fifo_p11[write_fifo_ptr] <= word_pixel(
                        (pipe_bank[BANK_READ_STAGES-1][3] == 0) ? bank0_rd_data
                        : (pipe_bank[BANK_READ_STAGES-1][3] == 1) ? bank1_rd_data
                        : (pipe_bank[BANK_READ_STAGES-1][3] == 2) ? bank2_rd_data
                        : bank3_rd_data,
                        pipe_slot[BANK_READ_STAGES-1][3]
                    );
                    fifo_coord[write_fifo_ptr] <= 1'b1;
                end
                if (fifo_wr_ptr == RESPONSE_FIFO_DEPTH-1)
                    fifo_wr_ptr <= 0;
                else
                    fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
            end
            if (response_pop) begin
                if (fifo_rd_ptr == RESPONSE_FIFO_DEPTH-1)
                    fifo_rd_ptr <= 0;
                else
                    fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
            end
            case ({response_push, response_pop})
                2'b10: fifo_count <= fifo_count + 1;
                2'b01: fifo_count <= fifo_count - 1;
                default: fifo_count <= fifo_count;
            endcase

            if (lookup_fire && request_miss) begin
                pending_tile_x <= missing_tile_x_comb;
                pending_tile_y <= missing_tile_y_comb;
                pending_set <= missing_set_comb;
                pending_way <= selected_way_comb;
                pending_row <= 0;
                miss_retry_valid <= 1'b1;
                miss_retry_x <= decode_x;
                miss_retry_y <= decode_y;
                valid_mem[missing_set_comb][selected_way_comb] <= 1'b0;
                fill_state <= FILL_REQ;
            end else if (retry_fire) begin
                miss_retry_valid <= 1'b0;
            end else if ((fill_state == FILL_REQ)
                         && fill_req_valid && fill_req_ready) begin
                fill_state <= FILL_DATA;
            end else if ((fill_state == FILL_DATA)
                         && fill_data_valid && fill_data_ready
                         && fill_data_beat_index == 2'd3) begin
                if (pending_row == TILE_H - 1) begin
                    valid_mem[pending_set][pending_way] <= 1'b1;
                    tag_x_mem[pending_set][pending_way] <= pending_tile_x;
                    tag_y_mem[pending_set][pending_way] <= pending_tile_y;
                    if (USE_TREE_PLRU != 0)
                        plru_state_mem[pending_set]
                            <= plru_touch_state(plru_state_mem[pending_set], pending_way);
                    else
                        touch_lru(pending_set, pending_way);
                    fill_state <= FILL_IDLE;
                end else begin
                    pending_row <= pending_row + 1'b1;
                    fill_state <= FILL_REQ;
                end
            end

            if (lookup_fire && request_hit)
                for (reset_bank_i = 0; reset_bank_i < 4; reset_bank_i = reset_bank_i + 1)
                    if (USE_TREE_PLRU != 0)
                        plru_state_mem[req_set[reset_bank_i]]
                            <= plru_touch_state(
                                plru_state_mem[req_set[reset_bank_i]],
                                req_way[reset_bank_i]
                            );
                    else
                        touch_lru(req_set[reset_bank_i], req_way[reset_bank_i]);
        end
    end
endmodule

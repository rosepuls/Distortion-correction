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
    // Keep enough response credits for S0, S1, S2 and the synchronous Bank
    // pipeline.  The cache engine metadata FIFO has eight entries, so this
    // remains bounded while allowing a full-rate hit stream to fill the new
    // front-end pipeline without an acceptance bubble.
    localparam integer RESPONSE_FIFO_DEPTH = BANK_READ_STAGES + 4;
    localparam integer FIFO_PTR_WIDTH = (RESPONSE_FIFO_DEPTH <= 2)
                                        ? 1 : $clog2(RESPONSE_FIFO_DEPTH);
    localparam integer FIFO_COUNT_WIDTH = (RESPONSE_FIFO_DEPTH <= 1)
                                          ? 1 : $clog2(RESPONSE_FIFO_DEPTH + 1);
    localparam integer OCCUPANCY_WIDTH = $clog2(
        RESPONSE_FIFO_DEPTH + BANK_READ_STAGES + 5
    );

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
    reg invalidate_pending;
    reg invalidate_active;
    reg [SET_WIDTH-1:0] invalidate_set;
    // A request that has completed its Tag probe but has not yet entered S2
    // contains stale hit/miss bits whenever Tags change (a refill completes
    // or a frame invalidation clears a set).  Preserve it, let it advance to
    // S2, then route it through the normal registered retry path before it
    // can reach replacement or the bank read.
    reg s1_tag_recheck_pending;

    // S0 owns the accepted external lookup.  All address decode, tag probes
    // and miss control below consume this register rather than the incoming
    // FIFO/cache-engine wires, cutting the long FIFO-to-Cache combinational
    // cone.  A hit may replace S0 in the same cycle; a miss blocks younger
    // requests until its refill/retry completes.
    reg s0_valid;
    reg [COORD_WIDTH-1:0] s0_x0;
    reg [COORD_WIDTH-1:0] s0_y0;

    // S1 contains only fixed-width address-decode results.  No tag or
    // replacement decision is allowed to feed back into this stage.
    reg s1_valid;
    reg s1_coord_valid;
    reg [COORD_WIDTH-1:0] s1_tile_x [0:3];
    reg [COORD_WIDTH-1:0] s1_tile_y [0:3];
    reg [SET_WIDTH-1:0] s1_set [0:3];
    reg [4:0] s1_local_x [0:3];
    reg [1:0] s1_local_y [0:3];
    reg [1:0] s1_bank [0:3];
    reg [1:0] s1_slot [0:3];

    // S1 Tag registers split the four-way Tag comparison from first-miss
    // selection.  This keeps the normal lookup path from forming the long
    // s1_set -> Tag compare -> summary/first-miss -> S2 cone reported by PDS.
    reg s1_tag_valid;
    reg s1_tag_coord_valid;
    reg [COORD_WIDTH-1:0] s1_tag_tile_x [0:3];
    reg [COORD_WIDTH-1:0] s1_tag_tile_y [0:3];
    reg [SET_WIDTH-1:0] s1_tag_set [0:3];
    reg [4:0] s1_tag_local_x [0:3];
    reg [1:0] s1_tag_local_y [0:3];
    reg [WAY_WIDTH-1:0] s1_tag_way [0:3];
    reg [1:0] s1_tag_bank [0:3];
    reg [1:0] s1_tag_slot [0:3];
    reg s1_tag_hit [0:3];

    // S2 owns the registered Tag summary.  A miss remains here while refill
    // runs; younger S1/S0 requests are frozen and therefore cannot overtake
    // it.  A completed refill retries the held address through dedicated
    // address, Tag-probe and result registers, so the refill-only recheck
    // cannot form a s2_set -> Tag -> s2_missing combinational feedback path.
    reg s2_valid;
    reg s2_retry_capture_pending /* synthesis syn_preserve = 1 */;
    reg s2_retry_probe_pending /* synthesis syn_preserve = 1 */;
    reg s2_retry_result_pending /* synthesis syn_preserve = 1 */;
    reg s2_coord_valid;
    reg [COORD_WIDTH-1:0] s2_tile_x [0:3];
    reg [COORD_WIDTH-1:0] s2_tile_y [0:3];
    reg [SET_WIDTH-1:0] s2_set [0:3];
    reg [4:0] s2_local_x [0:3];
    reg [1:0] s2_local_y [0:3];
    reg [WAY_WIDTH-1:0] s2_way [0:3];
    reg [1:0] s2_bank [0:3];
    reg [1:0] s2_slot [0:3];
    reg s2_all_hit;
    reg s2_missing_found;
    reg [COORD_WIDTH-1:0] s2_missing_tile_x;
    reg [COORD_WIDTH-1:0] s2_missing_tile_y;
    reg [SET_WIDTH-1:0] s2_missing_set;

    // Refill retry pipeline.  It is only active while the held S2 request is
    // being re-probed; normal lookups use the S0 -> S1 -> S1 Tag -> S2 path.
    reg [COORD_WIDTH-1:0] retry_tile_x [0:3]
        /* synthesis syn_preserve = 1 */;
    reg [COORD_WIDTH-1:0] retry_tile_y [0:3]
        /* synthesis syn_preserve = 1 */;
    reg [SET_WIDTH-1:0] retry_set [0:3]
        /* synthesis syn_preserve = 1 */;
    reg retry_tag_hit [0:3] /* synthesis syn_preserve = 1 */;
    reg [WAY_WIDTH-1:0] retry_tag_way [0:3]
        /* synthesis syn_preserve = 1 */;

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

    reg [COORD_WIDTH-1:0] decode_req_x [0:3];
    reg [COORD_WIDTH-1:0] decode_req_y [0:3];
    reg [COORD_WIDTH-1:0] decode_tile_x [0:3];
    reg [COORD_WIDTH-1:0] decode_tile_y [0:3];
    reg [SET_WIDTH-1:0] decode_set [0:3];
    reg [4:0] decode_local_x [0:3];
    reg [1:0] decode_local_y [0:3];
    reg [1:0] decode_bank [0:3];
    reg [1:0] decode_slot [0:3];
    reg decode_coord_valid;

    reg tag_hit_comb [0:3];
    reg [WAY_WIDTH-1:0] tag_way_comb [0:3];
    reg s1_tag_all_hit_comb;
    reg s1_tag_missing_found_comb;
    reg [COORD_WIDTH-1:0] s1_tag_missing_tile_x_comb;
    reg [COORD_WIDTH-1:0] s1_tag_missing_tile_y_comb;
    reg [SET_WIDTH-1:0] s1_tag_missing_set_comb;
    reg retry_all_hit_comb;
    reg retry_missing_found_comb;
    reg [COORD_WIDTH-1:0] retry_missing_tile_x_comb;
    reg [COORD_WIDTH-1:0] retry_missing_tile_y_comb;
    reg [SET_WIDTH-1:0] retry_missing_set_comb;
    reg retry_probe_hit_comb [0:3];
    reg [WAY_WIDTH-1:0] retry_probe_way_comb [0:3];
    reg [WAY_WIDTH-1:0] selected_way_comb;
    reg selected_invalid_comb;
    reg [WAY_WIDTH-1:0] best_rank_comb;
    integer decode_i;
    integer tag_i;
    integer tag_way_i;
    integer retry_i;
    integer retry_way_i;
    integer victim_way_i;

    function automatic [SET_WIDTH-1:0] tile_set_index(
        input [COORD_WIDTH-1:0] tile_x,
        input [COORD_WIDTH-1:0] tile_y
    );
        reg [COORD_WIDTH:0] set_hash;
        begin
            // SET_COUNT is constrained to a power of two.  The low bits are
            // the exact modulo result for both positive and negative
            // two's-complement skew values, with no divider or bmsSMOD.
            set_hash = {1'b0, tile_x} - {1'b0, tile_y}
                       + ({1'b0, tile_x} >> 2);
            tile_set_index = set_hash[SET_WIDTH-1:0];
        end
    endfunction

    function automatic [BANK_ADDR_WIDTH-1:0] bank_word_index(
        input [SET_WIDTH-1:0] set_index_value,
        input [WAY_WIDTH-1:0] way_index,
        input [4:0] local_x,
        input [1:0] local_y
    );
        begin
            if ((SET_COUNT == 32) && (TILE_W == 32) && (TILE_H == 4)
                && (WAYS == 8))
                bank_word_index = {set_index_value, way_index,
                                   local_y[1], local_x[4:3]};
            else if ((SET_COUNT == 16) && (TILE_W == 32) && (TILE_H == 4)
                     && (WAYS == 4))
                bank_word_index = {set_index_value, way_index,
                                   local_y[1], local_x[4:3]};
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

    function automatic [WAY_WIDTH-1:0] plru_victim_index(
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

    // S1 combinational input: fixed Tile/local-coordinate arithmetic only.
    // Every result is captured before any metadata lookup begins.
    always @* begin
        decode_req_x[0] = s0_x0;
        decode_req_y[0] = s0_y0;
        decode_req_x[1] = s0_x0 + 1'b1;
        decode_req_y[1] = s0_y0;
        decode_req_x[2] = s0_x0;
        decode_req_y[2] = s0_y0 + 1'b1;
        decode_req_x[3] = s0_x0 + 1'b1;
        decode_req_y[3] = s0_y0 + 1'b1;
        decode_coord_valid = (s0_x0 < IMAGE_WIDTH - 1)
                             && (s0_y0 < IMAGE_HEIGHT - 1);

        for (decode_i = 0; decode_i < 4; decode_i = decode_i + 1) begin
            decode_tile_x[decode_i] = decode_req_x[decode_i] >> 5;
            decode_tile_y[decode_i] = decode_req_y[decode_i] >> 2;
            decode_local_x[decode_i] = decode_req_x[decode_i] & 31;
            decode_local_y[decode_i] = decode_req_y[decode_i] & 3;
            decode_set[decode_i] = tile_set_index(
                decode_tile_x[decode_i], decode_tile_y[decode_i]
            );
            decode_bank[decode_i] = {decode_local_y[decode_i][0],
                                     decode_local_x[decode_i][0]};
            decode_slot[decode_i] = decode_local_x[decode_i][2:1];
        end
    end

    // Normal Tag probe: only per-neighborhood four-way comparisons are made
    // from registered S1 addresses in this cycle.  The all-hit and first-miss
    // summary is deferred until the registered S1 Tag stage reaches S2.
    always @* begin
        for (tag_i = 0; tag_i < 4; tag_i = tag_i + 1) begin
            tag_hit_comb[tag_i] = 1'b0;
            tag_way_comb[tag_i] = {WAY_WIDTH{1'b0}};
            for (tag_way_i = 0; tag_way_i < WAYS; tag_way_i = tag_way_i + 1)
                if (valid_mem[s1_set[tag_i]][tag_way_i]
                    && tag_x_mem[s1_set[tag_i]][tag_way_i]
                       == s1_tile_x[tag_i]
                    && tag_y_mem[s1_set[tag_i]][tag_way_i]
                       == s1_tile_y[tag_i]) begin
                    tag_hit_comb[tag_i] = 1'b1;
                    tag_way_comb[tag_i] = tag_way_i;
                end
        end
    end

    // missing_found is explicit so Tile (0,0) is a normal address.
    always @* begin
        s1_tag_all_hit_comb = 1'b1;
        s1_tag_missing_found_comb = 1'b0;
        s1_tag_missing_tile_x_comb = {COORD_WIDTH{1'b0}};
        s1_tag_missing_tile_y_comb = {COORD_WIDTH{1'b0}};
        s1_tag_missing_set_comb = {SET_WIDTH{1'b0}};
        for (tag_i = 0; tag_i < 4; tag_i = tag_i + 1)
            if (!s1_tag_hit[tag_i]) begin
                s1_tag_all_hit_comb = 1'b0;
                if (!s1_tag_missing_found_comb) begin
                    s1_tag_missing_found_comb = 1'b1;
                    s1_tag_missing_tile_x_comb = s1_tag_tile_x[tag_i];
                    s1_tag_missing_tile_y_comb = s1_tag_tile_y[tag_i];
                    s1_tag_missing_set_comb = s1_tag_set[tag_i];
                end
            end
    end

    // Refill retry Tag probe.  This stage contains only the per-neighborhood
    // four-way comparisons.  Selecting the first missing neighborhood is
    // intentionally deferred to retry_result_pending in the next cycle.
    always @* begin
        for (retry_i = 0; retry_i < 4; retry_i = retry_i + 1) begin
            retry_probe_hit_comb[retry_i] = 1'b0;
            retry_probe_way_comb[retry_i] = {WAY_WIDTH{1'b0}};
            for (retry_way_i = 0; retry_way_i < WAYS;
                 retry_way_i = retry_way_i + 1)
                if (valid_mem[retry_set[retry_i]][retry_way_i]
                    && tag_x_mem[retry_set[retry_i]][retry_way_i]
                       == retry_tile_x[retry_i]
                    && tag_y_mem[retry_set[retry_i]][retry_way_i]
                       == retry_tile_y[retry_i]) begin
                    retry_probe_hit_comb[retry_i] = 1'b1;
                    retry_probe_way_comb[retry_i] = retry_way_i;
                end
        end
    end

    always @* begin
        retry_all_hit_comb = 1'b1;
        retry_missing_found_comb = 1'b0;
        retry_missing_tile_x_comb = {COORD_WIDTH{1'b0}};
        retry_missing_tile_y_comb = {COORD_WIDTH{1'b0}};
        retry_missing_set_comb = {SET_WIDTH{1'b0}};
        for (retry_i = 0; retry_i < 4; retry_i = retry_i + 1)
            if (!retry_tag_hit[retry_i]) begin
                retry_all_hit_comb = 1'b0;
                if (!retry_missing_found_comb) begin
                    retry_missing_found_comb = 1'b1;
                    retry_missing_tile_x_comb = retry_tile_x[retry_i];
                    retry_missing_tile_y_comb = retry_tile_y[retry_i];
                    retry_missing_set_comb = retry_set[retry_i];
                end
            end
    end

    wire request_hit = s2_valid && s2_coord_valid && s2_all_hit;
    wire request_black = s2_valid && !s2_coord_valid;
    wire request_miss = s2_valid && s2_coord_valid && !s2_all_hit;

    // Victim selection is intentionally downstream of the registered S2 Tag
    // result and is active only for a real miss.  It can no longer absorb the
    // coordinate decode and four Tag comparisons into the metadata write.
    always @* begin
        selected_way_comb = 0;
        selected_invalid_comb = 1'b0;
        best_rank_comb = 0;
        if (request_miss && s2_missing_found) begin
            for (victim_way_i = 0; victim_way_i < WAYS;
                 victim_way_i = victim_way_i + 1) begin
                if (!valid_mem[s2_missing_set][victim_way_i]
                    && !selected_invalid_comb) begin
                    selected_way_comb = victim_way_i;
                    selected_invalid_comb = 1'b1;
                end
            end
            if (!selected_invalid_comb) begin
                if (USE_TREE_PLRU != 0) begin
                    selected_way_comb = plru_victim_index(
                        plru_state_mem[s2_missing_set]
                    );
                end else begin
                    selected_way_comb = 0;
                    best_rank_comb = 0;
                    for (victim_way_i = 0; victim_way_i < WAYS;
                         victim_way_i = victim_way_i + 1)
                        if (valid_mem[s2_missing_set][victim_way_i]
                            && (lru_rank_mem[s2_missing_set][victim_way_i]
                                >= best_rank_comb)) begin
                            best_rank_comb = lru_rank_mem[s2_missing_set][victim_way_i];
                            selected_way_comb = victim_way_i;
                        end
                end
            end
        end
    end

    // Hit/black response pipeline.  The pipeline token and the synchronous
    // bank output have identical latency, so no per-hit bubble is introduced.
    reg [1:0] pipe_kind [0:BANK_READ_STAGES-1];
    reg [1:0] pipe_bank [0:BANK_READ_STAGES-1][0:3];
    reg [1:0] pipe_slot [0:BANK_READ_STAGES-1][0:3];
    reg [FIFO_COUNT_WIDTH-1:0] pipe_valid_count;
    integer pipe_i;
    always @* begin
        pipe_valid_count = {FIFO_COUNT_WIDTH{1'b0}};
        for (pipe_i = 0; pipe_i < BANK_READ_STAGES; pipe_i = pipe_i + 1)
            if (pipe_kind[pipe_i] != PIPE_EMPTY)
                pipe_valid_count = pipe_valid_count + 1'b1;
    end

    reg [FIFO_COUNT_WIDTH-1:0] fifo_count;
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

    wire response_pop = lookup_rsp_valid && lookup_rsp_ready;
    wire [OCCUPANCY_WIDTH-1:0] lookup_occupied = fifo_count
        + pipe_valid_count + s0_valid + s1_valid + s1_tag_valid + s2_valid;
    wire lookup_capacity = (lookup_occupied < RESPONSE_FIFO_DEPTH)
                           || response_pop;
    wire pipeline_operational = rst_n && !invalidate && !invalidate_pending
                                && !invalidate_active
                                && (fill_state == FILL_IDLE);
    // S2 hit/black requests retire into the Bank/response pipeline.  An S2
    // miss or a post-refill Tag retry freezes every younger stage.
    wire retry_active = s2_retry_capture_pending || s2_retry_probe_pending
                        || s2_retry_result_pending;
    wire pipeline_advance = pipeline_operational && !retry_active
                            && (!s2_valid || !request_miss);
    assign lookup_ready = pipeline_advance && lookup_capacity;
    wire external_lookup_fire = lookup_valid && lookup_ready;
    wire s2_fire = pipeline_advance && s2_valid;
    wire start_miss = pipeline_operational && s2_valid && request_miss
                      && !retry_active;
    wire bank_read_en = s2_fire && request_hit;

    reg [BANK_ADDR_WIDTH-1:0] bank_rd_addr_comb [0:3];
    integer bank_addr_i;
    always @* begin
        for (bank_addr_i = 0; bank_addr_i < 4; bank_addr_i = bank_addr_i + 1)
            bank_rd_addr_comb[bank_addr_i] = {BANK_ADDR_WIDTH{1'b0}};
        if (request_hit)
            for (bank_addr_i = 0; bank_addr_i < 4; bank_addr_i = bank_addr_i + 1)
                bank_rd_addr_comb[s2_bank[bank_addr_i]] = bank_word_index(
                    s2_set[bank_addr_i], s2_way[bank_addr_i],
                    s2_local_x[bank_addr_i], s2_local_y[bank_addr_i]
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
            invalidate_pending <= 1'b0;
            invalidate_active <= 1'b0;
            invalidate_set <= 0;
            s1_tag_recheck_pending <= 1'b0;
            s0_valid <= 1'b0;
            s0_x0 <= 0;
            s0_y0 <= 0;
            s1_valid <= 1'b0;
            s1_tag_valid <= 1'b0;
            s2_valid <= 1'b0;
            s2_retry_capture_pending <= 1'b0;
            s2_retry_probe_pending <= 1'b0;
            s2_retry_result_pending <= 1'b0;
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
            // Advance S0 -> S1 decode -> S1 Tag -> S2 summary as one elastic
            // front pipeline.  A held S2 miss stops all four stages, preserving
            // request order without sacrificing one-per-cycle hit flow.
            if (pipeline_advance) begin
                s0_valid <= external_lookup_fire;
                if (external_lookup_fire) begin
                    s0_x0 <= lookup_x0;
                    s0_y0 <= lookup_y0;
                end

                s1_valid <= s0_valid;
                if (s0_valid) begin
                    s1_coord_valid <= decode_coord_valid;
                    for (reset_bank_i = 0; reset_bank_i < 4;
                         reset_bank_i = reset_bank_i + 1) begin
                        s1_tile_x[reset_bank_i] <= decode_tile_x[reset_bank_i];
                        s1_tile_y[reset_bank_i] <= decode_tile_y[reset_bank_i];
                        s1_set[reset_bank_i] <= decode_set[reset_bank_i];
                        s1_local_x[reset_bank_i] <= decode_local_x[reset_bank_i];
                        s1_local_y[reset_bank_i] <= decode_local_y[reset_bank_i];
                        s1_bank[reset_bank_i] <= decode_bank[reset_bank_i];
                        s1_slot[reset_bank_i] <= decode_slot[reset_bank_i];
                    end
                end

                s1_tag_valid <= s1_valid;
                if (s1_valid) begin
                    s1_tag_coord_valid <= s1_coord_valid;
                    for (reset_bank_i = 0; reset_bank_i < 4;
                         reset_bank_i = reset_bank_i + 1) begin
                        s1_tag_tile_x[reset_bank_i] <= s1_tile_x[reset_bank_i];
                        s1_tag_tile_y[reset_bank_i] <= s1_tile_y[reset_bank_i];
                        s1_tag_set[reset_bank_i] <= s1_set[reset_bank_i];
                        s1_tag_local_x[reset_bank_i] <= s1_local_x[reset_bank_i];
                        s1_tag_local_y[reset_bank_i] <= s1_local_y[reset_bank_i];
                        s1_tag_way[reset_bank_i] <= tag_way_comb[reset_bank_i];
                        s1_tag_bank[reset_bank_i] <= s1_bank[reset_bank_i];
                        s1_tag_slot[reset_bank_i] <= s1_slot[reset_bank_i];
                        s1_tag_hit[reset_bank_i] <= tag_hit_comb[reset_bank_i];
                    end
                end

                s2_valid <= s1_tag_valid;
                if (s1_tag_valid) begin
                    s2_coord_valid <= s1_tag_coord_valid;
                    s2_all_hit <= s1_tag_all_hit_comb;
                    s2_missing_found <= s1_tag_missing_found_comb;
                    s2_missing_tile_x <= s1_tag_missing_tile_x_comb;
                    s2_missing_tile_y <= s1_tag_missing_tile_y_comb;
                    s2_missing_set <= s1_tag_missing_set_comb;
                    for (reset_bank_i = 0; reset_bank_i < 4;
                         reset_bank_i = reset_bank_i + 1) begin
                        s2_tile_x[reset_bank_i] <= s1_tag_tile_x[reset_bank_i];
                        s2_tile_y[reset_bank_i] <= s1_tag_tile_y[reset_bank_i];
                        s2_set[reset_bank_i] <= s1_tag_set[reset_bank_i];
                        s2_local_x[reset_bank_i] <= s1_tag_local_x[reset_bank_i];
                        s2_local_y[reset_bank_i] <= s1_tag_local_y[reset_bank_i];
                        s2_way[reset_bank_i] <= s1_tag_way[reset_bank_i];
                        s2_bank[reset_bank_i] <= s1_tag_bank[reset_bank_i];
                        s2_slot[reset_bank_i] <= s1_tag_slot[reset_bank_i];
                    end
                end
            end

            // Metadata written on the final refill beat becomes visible on
            // the following cycle.  Capture the held decoded address first,
            // then probe Tags, then commit the summary result.  S0/S1 remain
            // held for all three retry stages.
            if (s2_retry_capture_pending && (fill_state == FILL_IDLE)
                && !invalidate && !invalidate_pending && !invalidate_active) begin
                for (reset_bank_i = 0; reset_bank_i < 4;
                     reset_bank_i = reset_bank_i + 1) begin
                    retry_tile_x[reset_bank_i] <= s2_tile_x[reset_bank_i];
                    retry_tile_y[reset_bank_i] <= s2_tile_y[reset_bank_i];
                    retry_set[reset_bank_i] <= s2_set[reset_bank_i];
                end
                s2_retry_capture_pending <= 1'b0;
                s2_retry_probe_pending <= 1'b1;
            end else if (s2_retry_probe_pending && (fill_state == FILL_IDLE)
                         && !invalidate && !invalidate_pending
                         && !invalidate_active) begin
                for (reset_bank_i = 0; reset_bank_i < 4;
                     reset_bank_i = reset_bank_i + 1) begin
                    retry_tag_hit[reset_bank_i] <= retry_probe_hit_comb[reset_bank_i];
                    retry_tag_way[reset_bank_i] <= retry_probe_way_comb[reset_bank_i];
                end
                s2_retry_probe_pending <= 1'b0;
                s2_retry_result_pending <= 1'b1;
            end else if (s2_retry_result_pending && (fill_state == FILL_IDLE)
                         && !invalidate && !invalidate_pending
                         && !invalidate_active) begin
                s2_all_hit <= retry_all_hit_comb;
                s2_missing_found <= retry_missing_found_comb;
                s2_missing_tile_x <= retry_missing_tile_x_comb;
                s2_missing_tile_y <= retry_missing_tile_y_comb;
                s2_missing_set <= retry_missing_set_comb;
                for (reset_bank_i = 0; reset_bank_i < 4;
                     reset_bank_i = reset_bank_i + 1) begin
                    s2_way[reset_bank_i] <= retry_tag_way[reset_bank_i];
                end
                s2_retry_result_pending <= 1'b0;
            end

            // A frame boundary invalidates tags a set at a time.  This keeps
            // the operation bounded and avoids a large reset fanout while
            // guaranteeing that no tile from the previous frame can hit.
            if (invalidate)
                invalidate_pending <= 1'b1;

            if (invalidate_active) begin
                for (reset_way_i = 0; reset_way_i < WAYS; reset_way_i = reset_way_i + 1)
                    valid_mem[invalidate_set][reset_way_i] <= 1'b0;
                if (invalidate_set == SET_COUNT - 1) begin
                    invalidate_active <= 1'b0;
                    invalidate_set <= 0;
                    if (s2_valid)
                        s2_retry_capture_pending <= 1'b1;
                    if (s1_tag_valid)
                        s1_tag_recheck_pending <= 1'b1;
                end else begin
                    invalidate_set <= invalidate_set + 1'b1;
                end
            end else if ((invalidate_pending || invalidate)
                         && (fill_state == FILL_IDLE)) begin
                invalidate_pending <= 1'b0;
                invalidate_active <= 1'b1;
                invalidate_set <= 0;
            end

            // A Tag update may leave an older S1 Tag result behind the held
            // S2 request.  Once that result transfers to S2, freeze it and
            // reuse the three-stage retry path so Tags are re-probed.
            if (s1_tag_recheck_pending && !retry_active
                && pipeline_operational && s1_tag_valid) begin
                s2_retry_capture_pending <= 1'b1;
                s1_tag_recheck_pending <= 1'b0;
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
            if (s2_fire) begin
                if (request_black)
                    pipe_kind[0] <= PIPE_BLACK;
                else if (request_hit) begin
                    pipe_kind[0] <= PIPE_HIT;
                    for (reset_bank_i = 0; reset_bank_i < 4; reset_bank_i = reset_bank_i + 1) begin
                        pipe_bank[0][reset_bank_i] <= s2_bank[reset_bank_i];
                        pipe_slot[0][reset_bank_i] <= s2_slot[reset_bank_i];
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

            if (start_miss) begin
                pending_tile_x <= s2_missing_tile_x;
                pending_tile_y <= s2_missing_tile_y;
                pending_set <= s2_missing_set;
                pending_way <= selected_way_comb;
                pending_row <= 0;
                valid_mem[s2_missing_set][selected_way_comb] <= 1'b0;
                fill_state <= FILL_REQ;
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
                    s2_retry_capture_pending <= 1'b1;
                    if (s1_tag_valid)
                        s1_tag_recheck_pending <= 1'b1;
                end else begin
                    pending_row <= pending_row + 1'b1;
                    fill_state <= FILL_REQ;
                end
            end

            if (s2_fire && request_hit)
                for (reset_bank_i = 0; reset_bank_i < 4; reset_bank_i = reset_bank_i + 1)
                    if (USE_TREE_PLRU != 0)
                        plru_state_mem[s2_set[reset_bank_i]]
                            <= plru_touch_state(
                                plru_state_mem[s2_set[reset_bank_i]],
                                s2_way[reset_bank_i]
                            );
                    else
                        touch_lru(s2_set[reset_bank_i], s2_way[reset_bank_i]);
        end
    end
endmodule

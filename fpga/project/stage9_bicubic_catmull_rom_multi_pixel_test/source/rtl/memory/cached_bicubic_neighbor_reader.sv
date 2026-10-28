`timescale 1ns / 1ps

// Gather 4x4 bicubic neighborhoods using an ordered two-context queue.
// Each context issues its cache lookups back-to-back; cache responses are
// associated with the pixel/query that issued them through an ordered tag FIFO.
// Adjacent horizontal contexts reuse the previous output window's three columns.
module cached_bicubic_neighbor_reader #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer SET_COUNT = 16,
    parameter integer WAYS = 8,
    parameter integer BANK_READ_LATENCY = 1
) (
    input  wire         clk,
    input  wire         rstn,
    input  wire         source_frame_start,
    input  wire [1:0]   source_frame_slot,
    input  wire         s_valid,
    output wire         s_ready,
    input  wire [10:0]  s_x0, s_x1, s_x2, s_x3,
    input  wire [9:0]   s_y0, s_y1, s_y2, s_y3,
    input  wire [15:0]  s_fx,
    input  wire [15:0]  s_fy,
    input  wire [15:0]  s_neighbor_valid,
    input  wire         s_geometry_valid,
    input  wire [19:0]  s_pixel_id,
    input  wire [31:0]  s_frame_id,
    input  wire [15:0]  s_param_version,
    input  wire         s_sof,
    input  wire         s_eol,
    input  wire         s_eof,
    output reg          m_valid,
    input  wire         m_ready,
    output reg [511:0]  m_samples,
    output reg [15:0]   m_fx,
    output reg [15:0]   m_fy,
    output reg [15:0]   m_neighbor_valid,
    output reg          m_geometry_valid,
    output reg [19:0]   m_pixel_id,
    output reg [31:0]   m_frame_id,
    output reg [15:0]   m_param_version,
    output reg          m_sof,
    output reg          m_eol,
    output reg          m_eof,
    output wire         read_valid,
    output wire [27:0]  read_addr,
    output wire [3:0]   read_len,
    output wire         read_reserve,
    input  wire         read_ready,
    input  wire         read_rvalid,
    input  wire [255:0] read_rdata,
    input  wire         read_rlast,
    output wire         idle,
    output wire         fatal_fault,
    output wire [15:0]  read_error_count,
    output wire [31:0]  fetched_rows,
    output wire [23:0]  diagnostic_miss_count,
    output wire [23:0]  diagnostic_fill_cycles,
    output wire         read_response_wait,
    output wire         first_beat_wait,
    output wire         interbeat_wait
);
    localparam integer CONTEXT_DEPTH = 2;
    localparam integer TAG_DEPTH = 8;
    localparam [1:0] CTX_COUNT_MAX = 2'd2;
    localparam [3:0] TAG_COUNT_MAX = 4'd8;

    reg ctx_head, ctx_tail;
    reg [1:0] ctx_count;
    reg [10:0] ctx_x0 [0:CONTEXT_DEPTH-1];
    reg [10:0] ctx_x2 [0:CONTEXT_DEPTH-1];
    reg [10:0] ctx_x3 [0:CONTEXT_DEPTH-1];
    reg [9:0] ctx_y0 [0:CONTEXT_DEPTH-1];
    reg [9:0] ctx_y2 [0:CONTEXT_DEPTH-1];
    reg [2:0] ctx_query_total [0:CONTEXT_DEPTH-1];
    reg [2:0] ctx_issued [0:CONTEXT_DEPTH-1];
    reg [2:0] ctx_returned [0:CONTEXT_DEPTH-1];
    reg ctx_reuse [0:CONTEXT_DEPTH-1];
    reg ctx_geometry_valid [0:CONTEXT_DEPTH-1];
    reg [511:0] ctx_samples [0:CONTEXT_DEPTH-1];
    reg [15:0] ctx_fx [0:CONTEXT_DEPTH-1];
    reg [15:0] ctx_fy [0:CONTEXT_DEPTH-1];
    reg [15:0] ctx_neighbor_valid [0:CONTEXT_DEPTH-1];
    reg [19:0] ctx_pixel_id [0:CONTEXT_DEPTH-1];
    reg [31:0] ctx_frame_id [0:CONTEXT_DEPTH-1];
    reg [15:0] ctx_param_version [0:CONTEXT_DEPTH-1];
    reg ctx_sof [0:CONTEXT_DEPTH-1];
    reg ctx_eol [0:CONTEXT_DEPTH-1];
    reg ctx_eof [0:CONTEXT_DEPTH-1];

    reg [2:0] tag_context [0:TAG_DEPTH-1];
    reg [1:0] tag_query [0:TAG_DEPTH-1];
    reg [2:0] tag_wr_ptr, tag_rd_ptr;
    reg [3:0] tag_count;

    reg [1:0] active_slot;
    reg frame_start_fault;
    reg context_fault;
    reg tail_window_valid;
    reg [10:0] tail_window_x0;
    reg [9:0] tail_window_y0;
    reg last_output_window_valid;
    reg [511:0] last_output_window;

    wire cache_lookup_valid;
    wire cache_lookup_ready;
    wire cache_rsp_valid, cache_rsp_ready;
    wire cache_invalidate;
    wire [31:0] cache_p00, cache_p10, cache_p01, cache_p11;
    wire cache_coord_valid, cache_hit;
    wire cache_fill_valid, cache_fill_ready;
    wire [11:0] cache_tile_x, cache_tile_y;
    wire [1:0] cache_row;
    wire adapter_data_valid, adapter_data_ready;
    wire [255:0] adapter_data;
    wire [11:0] adapter_tile_x, adapter_tile_y;
    wire [1:0] adapter_row, adapter_beat;
    wire adapter_idle, adapter_fault;
    wire [23:0] cache_miss_count, cache_fill_cycles;

    reg issue_found;
    reg issue_slot;
    reg [2:0] issue_query;
    reg [11:0] lookup_x, lookup_y;
    integer row_i;
    wire cache_idle = (ctx_count == 0) && (tag_count == 0) &&
                      adapter_idle && !cache_rsp_valid;
    wire accept = s_valid && s_ready;
    wire output_fire = m_valid && m_ready;
    wire lookup_fire = cache_lookup_valid && cache_lookup_ready;
    wire response_fire = cache_rsp_valid && cache_rsp_ready;
    wire [11:0] input_x0_ext = {1'b0, s_x0};
    wire [11:0] tail_x0_ext = {1'b0, tail_window_x0};
    wire regular_stencil = (s_x1 == s_x0 + 11'd1) &&
                           (s_x2 == s_x0 + 11'd2) &&
                           (s_x3 == s_x0 + 11'd3) &&
                           (s_y1 == s_y0 + 10'd1) &&
                           (s_y2 == s_y0 + 10'd2) &&
                           (s_y3 == s_y0 + 10'd3);
    wire can_reuse_window = tail_window_valid && regular_stencil &&
                            s_geometry_valid &&
                            (s_neighbor_valid == 16'hffff) &&
                            (input_x0_ext == (tail_x0_ext + 12'd1)) &&
                            (s_y0 == tail_window_y0);
    wire [2:0] input_query_total =
        (s_geometry_valid && (s_neighbor_valid == 16'hffff))
        ? (can_reuse_window ? 3'd2 : 3'd4) : 3'd0;

    assign fatal_fault = adapter_fault || frame_start_fault || context_fault;
    assign s_ready = rstn && (ctx_count < CTX_COUNT_MAX) &&
                     !source_frame_start && !fatal_fault;
    assign cache_rsp_ready = (tag_count != 0);
    assign cache_invalidate = source_frame_start && cache_idle;
    assign idle = cache_idle && !fatal_fault;

    always @* begin
        issue_found = 1'b0;
        issue_slot = ctx_head;
        issue_query = 3'd0;
        if (ctx_count != 0) begin
            if (ctx_issued[ctx_head] < ctx_query_total[ctx_head]) begin
                issue_found = 1'b1;
                issue_slot = ctx_head;
                issue_query = ctx_issued[ctx_head];
            end else if (ctx_count == CTX_COUNT_MAX &&
                         ctx_issued[~ctx_head] < ctx_query_total[~ctx_head]) begin
                issue_found = 1'b1;
                issue_slot = ~ctx_head;
                issue_query = ctx_issued[~ctx_head];
            end
        end

        lookup_x = 12'd0;
        lookup_y = 12'd0;
        if (issue_found) begin
            lookup_x = ctx_reuse[issue_slot]
                ? {1'b0, ctx_x3[issue_slot]}
                : issue_query[0] ? {1'b0, ctx_x2[issue_slot]}
                                 : {1'b0, ctx_x0[issue_slot]};
            lookup_y = (ctx_reuse[issue_slot] ? issue_query[0]
                                              : issue_query[1])
                ? {2'b0, ctx_y2[issue_slot]} : {2'b0, ctx_y0[issue_slot]};
        end

        m_valid = (ctx_count != 0) && !fatal_fault &&
                  (ctx_returned[ctx_head] == ctx_query_total[ctx_head]) &&
                  (!ctx_reuse[ctx_head] || last_output_window_valid);
        m_samples = (ctx_count != 0) ? ctx_samples[ctx_head] : 512'd0;
        if (ctx_count != 0 && ctx_reuse[ctx_head] &&
            last_output_window_valid) begin
            for (row_i = 0; row_i < 4; row_i = row_i + 1) begin
                m_samples[(row_i*4+0)*32 +: 32] =
                    last_output_window[(row_i*4+1)*32 +: 32];
                m_samples[(row_i*4+1)*32 +: 32] =
                    last_output_window[(row_i*4+2)*32 +: 32];
                m_samples[(row_i*4+2)*32 +: 32] =
                    last_output_window[(row_i*4+3)*32 +: 32];
            end
        end
        m_fx = (ctx_count != 0) ? ctx_fx[ctx_head] : 16'd0;
        m_fy = (ctx_count != 0) ? ctx_fy[ctx_head] : 16'd0;
        m_neighbor_valid = (ctx_count != 0)
            ? ctx_neighbor_valid[ctx_head] : 16'd0;
        m_geometry_valid = (ctx_count != 0) &&
                           ctx_geometry_valid[ctx_head];
        m_pixel_id = (ctx_count != 0) ? ctx_pixel_id[ctx_head] : 20'd0;
        m_frame_id = (ctx_count != 0) ? ctx_frame_id[ctx_head] : 32'd0;
        m_param_version = (ctx_count != 0)
            ? ctx_param_version[ctx_head] : 16'd0;
        m_sof = (ctx_count != 0) && ctx_sof[ctx_head];
        m_eol = (ctx_count != 0) && ctx_eol[ctx_head];
        m_eof = (ctx_count != 0) && ctx_eof[ctx_head];
    end

    assign cache_lookup_valid = issue_found && (tag_count < TAG_COUNT_MAX) &&
                                !source_frame_start && !fatal_fault;

    pixel_tile_cache #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .SET_COUNT(SET_COUNT), .WAYS(WAYS),
        .BANK_READ_LATENCY(BANK_READ_LATENCY)
    ) cache (
        .clk(clk), .rst_n(rstn), .invalidate(cache_invalidate),
        .lookup_valid(cache_lookup_valid), .lookup_ready(cache_lookup_ready),
        .lookup_x0(lookup_x), .lookup_y0(lookup_y),
        .lookup_rsp_valid(cache_rsp_valid), .lookup_rsp_ready(cache_rsp_ready),
        .pixel_p00(cache_p00), .pixel_p10(cache_p10),
        .pixel_p01(cache_p01), .pixel_p11(cache_p11),
        .cache_hit(cache_hit), .coord_valid(cache_coord_valid),
        .fill_req_valid(cache_fill_valid), .fill_req_ready(cache_fill_ready),
        .fill_tile_x(cache_tile_x), .fill_tile_y(cache_tile_y),
        .fill_row_index(cache_row),
        .fill_data_valid(adapter_data_valid), .fill_data_ready(adapter_data_ready),
        .fill_data(adapter_data), .fill_data_row_index(adapter_row),
        .fill_data_beat_index(adapter_beat),
        .diagnostic_miss_count(cache_miss_count),
        .diagnostic_fill_cycles(cache_fill_cycles)
    );

    tile_row_ddr_adapter #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) row_adapter (
        .clk(clk), .rstn(rstn),
        .fill_req_valid(cache_fill_valid), .fill_req_ready(cache_fill_ready),
        .frame_slot(active_slot), .fill_tile_x(cache_tile_x),
        .fill_tile_y(cache_tile_y), .fill_row_index(cache_row),
        .read_valid(read_valid), .read_addr(read_addr),
        .read_len(read_len), .read_reserve(read_reserve),
        .read_ready(read_ready), .read_rvalid(read_rvalid),
        .read_rdata(read_rdata), .read_rlast(read_rlast),
        .fill_data_valid(adapter_data_valid),
        .fill_data_ready(adapter_data_ready), .fill_data(adapter_data),
        .fill_out_tile_x(adapter_tile_x), .fill_out_tile_y(adapter_tile_y),
        .fill_out_row_index(adapter_row), .fill_beat_index(adapter_beat),
        .idle(adapter_idle), .first_beat_wait(first_beat_wait),
        .interbeat_wait(interbeat_wait), .fatal_fault(adapter_fault),
        .protocol_error_count(read_error_count),
        .completed_rows(fetched_rows), .read_response_wait(read_response_wait)
    );

    integer reset_i;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            ctx_head <= 1'b0;
            ctx_tail <= 1'b0;
            ctx_count <= 2'd0;
            tag_wr_ptr <= 3'd0;
            tag_rd_ptr <= 3'd0;
            tag_count <= 4'd0;
            active_slot <= 2'd0;
            frame_start_fault <= 1'b0;
            context_fault <= 1'b0;
            tail_window_valid <= 1'b0;
            tail_window_x0 <= 11'd0;
            tail_window_y0 <= 10'd0;
            last_output_window_valid <= 1'b0;
            last_output_window <= 512'd0;
            for (reset_i = 0; reset_i < CONTEXT_DEPTH; reset_i = reset_i + 1) begin
                ctx_query_total[reset_i] <= 3'd0;
                ctx_issued[reset_i] <= 3'd0;
                ctx_returned[reset_i] <= 3'd0;
                ctx_reuse[reset_i] <= 1'b0;
                ctx_geometry_valid[reset_i] <= 1'b0;
                ctx_samples[reset_i] <= 512'd0;
                ctx_fx[reset_i] <= 16'd0;
                ctx_fy[reset_i] <= 16'd0;
                ctx_neighbor_valid[reset_i] <= 16'd0;
                ctx_pixel_id[reset_i] <= 20'd0;
                ctx_frame_id[reset_i] <= 32'd0;
                ctx_param_version[reset_i] <= 16'd0;
                ctx_sof[reset_i] <= 1'b0;
                ctx_eol[reset_i] <= 1'b0;
                ctx_eof[reset_i] <= 1'b0;
                ctx_x0[reset_i] <= 11'd0;
                ctx_x2[reset_i] <= 11'd0;
                ctx_x3[reset_i] <= 11'd0;
                ctx_y0[reset_i] <= 10'd0;
                ctx_y2[reset_i] <= 10'd0;
            end
        end else begin
            if (source_frame_start) begin
                tail_window_valid <= 1'b0;
                last_output_window_valid <= 1'b0;
                if (!cache_idle || source_frame_slot >= 2'd3)
                    frame_start_fault <= 1'b1;
                else
                    active_slot <= source_frame_slot;
            end

            if (accept) begin
                ctx_x0[ctx_tail] <= s_x0;
                ctx_x2[ctx_tail] <= s_x2;
                ctx_x3[ctx_tail] <= s_x3;
                ctx_y0[ctx_tail] <= s_y0;
                ctx_y2[ctx_tail] <= s_y2;
                ctx_query_total[ctx_tail] <= input_query_total;
                ctx_issued[ctx_tail] <= 3'd0;
                ctx_returned[ctx_tail] <= 3'd0;
                ctx_reuse[ctx_tail] <= can_reuse_window;
                ctx_geometry_valid[ctx_tail] <= input_query_total != 0;
                ctx_samples[ctx_tail] <= 512'd0;
                ctx_fx[ctx_tail] <= s_fx;
                ctx_fy[ctx_tail] <= s_fy;
                ctx_neighbor_valid[ctx_tail] <= (input_query_total != 0)
                    ? 16'hffff : 16'h0000;
                ctx_pixel_id[ctx_tail] <= s_pixel_id;
                ctx_frame_id[ctx_tail] <= s_frame_id;
                ctx_param_version[ctx_tail] <= s_param_version;
                ctx_sof[ctx_tail] <= s_sof;
                ctx_eol[ctx_tail] <= s_eol;
                ctx_eof[ctx_tail] <= s_eof;
                ctx_tail <= ~ctx_tail;
                if (ctx_count == 0)
                    ctx_head <= ctx_tail;
                tail_window_valid <= (input_query_total != 0);
                tail_window_x0 <= s_x0;
                tail_window_y0 <= s_y0;
            end

            if (lookup_fire) begin
                ctx_issued[issue_slot] <= ctx_issued[issue_slot] + 1'b1;
                tag_context[tag_wr_ptr] <= {2'b0, issue_slot};
                tag_query[tag_wr_ptr] <= issue_query[1:0];
                tag_wr_ptr <= tag_wr_ptr + 1'b1;
            end

            if (response_fire) begin
                if (tag_context[tag_rd_ptr] >= CONTEXT_DEPTH)
                    context_fault <= 1'b1;
                else begin
                    if (ctx_reuse[tag_context[tag_rd_ptr]]) begin
                        if (tag_query[tag_rd_ptr] == 2'd0) begin
                            ctx_samples[tag_context[tag_rd_ptr]][3*32 +: 32]
                                <= cache_p00;
                            ctx_samples[tag_context[tag_rd_ptr]][7*32 +: 32]
                                <= cache_p01;
                        end else begin
                            ctx_samples[tag_context[tag_rd_ptr]][11*32 +: 32]
                                <= cache_p00;
                            ctx_samples[tag_context[tag_rd_ptr]][15*32 +: 32]
                                <= cache_p01;
                        end
                    end else case (tag_query[tag_rd_ptr])
                        2'd0: begin
                            ctx_samples[tag_context[tag_rd_ptr]][0*32 +: 32]
                                <= cache_p00;
                            ctx_samples[tag_context[tag_rd_ptr]][1*32 +: 32]
                                <= cache_p10;
                            ctx_samples[tag_context[tag_rd_ptr]][4*32 +: 32]
                                <= cache_p01;
                            ctx_samples[tag_context[tag_rd_ptr]][5*32 +: 32]
                                <= cache_p11;
                        end
                        2'd1: begin
                            ctx_samples[tag_context[tag_rd_ptr]][2*32 +: 32]
                                <= cache_p00;
                            ctx_samples[tag_context[tag_rd_ptr]][3*32 +: 32]
                                <= cache_p10;
                            ctx_samples[tag_context[tag_rd_ptr]][6*32 +: 32]
                                <= cache_p01;
                            ctx_samples[tag_context[tag_rd_ptr]][7*32 +: 32]
                                <= cache_p11;
                        end
                        2'd2: begin
                            ctx_samples[tag_context[tag_rd_ptr]][8*32 +: 32]
                                <= cache_p00;
                            ctx_samples[tag_context[tag_rd_ptr]][9*32 +: 32]
                                <= cache_p10;
                            ctx_samples[tag_context[tag_rd_ptr]][12*32 +: 32]
                                <= cache_p01;
                            ctx_samples[tag_context[tag_rd_ptr]][13*32 +: 32]
                                <= cache_p11;
                        end
                        default: begin
                            ctx_samples[tag_context[tag_rd_ptr]][10*32 +: 32]
                                <= cache_p00;
                            ctx_samples[tag_context[tag_rd_ptr]][11*32 +: 32]
                                <= cache_p10;
                            ctx_samples[tag_context[tag_rd_ptr]][14*32 +: 32]
                                <= cache_p01;
                            ctx_samples[tag_context[tag_rd_ptr]][15*32 +: 32]
                                <= cache_p11;
                        end
                    endcase
                    ctx_returned[tag_context[tag_rd_ptr]] <=
                        ctx_returned[tag_context[tag_rd_ptr]] + 1'b1;
                end
                tag_rd_ptr <= tag_rd_ptr + 1'b1;
            end

            case ({lookup_fire, response_fire})
                2'b10: tag_count <= tag_count + 1'b1;
                2'b01: tag_count <= tag_count - 1'b1;
                default: tag_count <= tag_count;
            endcase

            if (output_fire) begin
                if (ctx_geometry_valid[ctx_head]) begin
                    last_output_window <= m_samples;
                    last_output_window_valid <= 1'b1;
                end else begin
                    last_output_window <= 512'd0;
                    last_output_window_valid <= 1'b0;
                end
                ctx_head <= ~ctx_head;
            end else if (ctx_count != 0 &&
                         ctx_reuse[ctx_head] &&
                         ctx_returned[ctx_head] == ctx_query_total[ctx_head] &&
                         !last_output_window_valid) begin
                context_fault <= 1'b1;
            end

            case ({accept, output_fire})
                2'b10: ctx_count <= ctx_count + 1'b1;
                2'b01: ctx_count <= ctx_count - 1'b1;
                default: ctx_count <= ctx_count;
            endcase
        end
    end
endmodule

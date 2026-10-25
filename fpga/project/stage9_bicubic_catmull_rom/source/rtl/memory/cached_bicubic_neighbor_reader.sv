`timescale 1ns / 1ps

// Gather a row-major 4x4 stencil through four ordered 2x2 Tile Cache lookups.
// Each accepted pixel request owns the reader until all four lookup responses
// have been assembled, so no sample or metadata can overtake another request.
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
    localparam [1:0] IDLE = 2'd0;
    localparam [1:0] LOOKUP = 2'd1;
    localparam [1:0] WAIT_RESPONSE = 2'd2;
    localparam [1:0] OUTPUT = 2'd3;

    reg [1:0] state;
    reg [1:0] subquery;
    reg [1:0] active_slot;
    reg frame_start_fault;
    reg [10:0] x0_reg, x2_reg;
    reg [9:0] y0_reg, y2_reg;

    wire cache_lookup_valid = state == LOOKUP && !fatal_fault;
    wire cache_lookup_ready;
    wire cache_rsp_valid, cache_rsp_ready;
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
    wire [11:0] lookup_x = subquery[0] ? {1'b0, x2_reg} : {1'b0, x0_reg};
    wire [11:0] lookup_y = subquery[1] ? {2'b0, y2_reg} : {2'b0, y0_reg};
    wire cache_idle = state == IDLE && adapter_idle && !cache_rsp_valid;
    wire cache_invalidate = source_frame_start && cache_idle;
    wire accept = s_valid && s_ready;
    wire response = m_valid && m_ready;

    assign fatal_fault = adapter_fault || frame_start_fault;
    assign s_ready = rstn && state == IDLE && cache_lookup_ready &&
                     !source_frame_start && !fatal_fault;
    assign cache_rsp_ready = 1'b1;
    assign idle = state == IDLE && cache_idle && !fatal_fault;
    assign diagnostic_miss_count = cache_miss_count;
    assign diagnostic_fill_cycles = cache_fill_cycles;

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
        .completed_rows(fetched_rows),
        .read_response_wait(read_response_wait)
    );

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            subquery <= 2'd0;
            active_slot <= 2'd0;
            frame_start_fault <= 1'b0;
            m_valid <= 1'b0;
            m_samples <= 512'd0;
            m_fx <= 16'd0; m_fy <= 16'd0;
            m_neighbor_valid <= 16'd0;
            m_geometry_valid <= 1'b0;
            m_pixel_id <= 20'd0; m_frame_id <= 32'd0;
            m_param_version <= 16'd0;
            m_sof <= 1'b0; m_eol <= 1'b0; m_eof <= 1'b0;
            x0_reg <= 11'd0; x2_reg <= 11'd0;
            y0_reg <= 10'd0; y2_reg <= 10'd0;
        end else begin
            if (source_frame_start) begin
                if (!cache_idle || source_frame_slot >= 2'd3)
                    frame_start_fault <= 1'b1;
                else
                    active_slot <= source_frame_slot;
            end

            if (accept) begin
                x0_reg <= s_x0; x2_reg <= s_x2;
                y0_reg <= s_y0; y2_reg <= s_y2;
                m_fx <= s_fx; m_fy <= s_fy;
                m_neighbor_valid <= (s_geometry_valid &&
                    s_neighbor_valid == 16'hffff) ? 16'hffff : 16'h0000;
                m_geometry_valid <= s_geometry_valid &&
                                    s_neighbor_valid == 16'hffff;
                m_pixel_id <= s_pixel_id; m_frame_id <= s_frame_id;
                m_param_version <= s_param_version;
                m_sof <= s_sof; m_eol <= s_eol; m_eof <= s_eof;
                m_samples <= 512'd0;
                subquery <= 2'd0;
                if (s_geometry_valid && s_neighbor_valid == 16'hffff) begin
                    m_valid <= 1'b0;
                    state <= LOOKUP;
                end else begin
                    m_valid <= 1'b1;
                    state <= OUTPUT;
                end
            end else begin
                case (state)
                    LOOKUP: if (cache_lookup_valid && cache_lookup_ready)
                        state <= WAIT_RESPONSE;
                    WAIT_RESPONSE: if (cache_rsp_valid) begin
                        case (subquery)
                            2'd0: begin
                                m_samples[0*32 +: 32] <= cache_p00;
                                m_samples[1*32 +: 32] <= cache_p10;
                                m_samples[4*32 +: 32] <= cache_p01;
                                m_samples[5*32 +: 32] <= cache_p11;
                            end
                            2'd1: begin
                                m_samples[2*32 +: 32] <= cache_p00;
                                m_samples[3*32 +: 32] <= cache_p10;
                                m_samples[6*32 +: 32] <= cache_p01;
                                m_samples[7*32 +: 32] <= cache_p11;
                            end
                            2'd2: begin
                                m_samples[8*32 +: 32] <= cache_p00;
                                m_samples[9*32 +: 32] <= cache_p10;
                                m_samples[12*32 +: 32] <= cache_p01;
                                m_samples[13*32 +: 32] <= cache_p11;
                            end
                            default: begin
                                m_samples[10*32 +: 32] <= cache_p00;
                                m_samples[11*32 +: 32] <= cache_p10;
                                m_samples[14*32 +: 32] <= cache_p01;
                                m_samples[15*32 +: 32] <= cache_p11;
                            end
                        endcase
                        if (subquery == 2'd3) begin
                            m_valid <= 1'b1;
                            state <= OUTPUT;
                        end else begin
                            subquery <= subquery + 1'b1;
                            state <= LOOKUP;
                        end
                    end
                    OUTPUT: if (response) begin
                        m_valid <= 1'b0;
                        state <= IDLE;
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule

`timescale 1ns / 1ps

// Tile Cache bridge for the common bilinear_sample_planner interface. The
// legacy cache probes x,x+1/y,y+1; this wrapper remaps clamped boundary
// neighbors to the correct one of its four returned pixels. All metadata is
// queued in the same order as accepted cache lookups.
module cached_neighbor_reader #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer SET_COUNT = 16,
    parameter integer WAYS = 4,
    parameter integer BANK_READ_LATENCY = 1
) (
    input  wire         clk,
    input  wire         rstn,
    input  wire         source_frame_start,
    input  wire [1:0]   source_frame_slot,
    input  wire         s_valid,
    output wire         s_ready,
    input  wire [10:0]  s_x0,
    input  wire [10:0]  s_x1,
    input  wire [9:0]   s_y0,
    input  wire [9:0]   s_y1,
    input  wire [15:0]  s_fx,
    input  wire [15:0]  s_fy,
    input  wire [3:0]   s_neighbor_valid,
    input  wire         s_geometry_valid,
    input  wire [19:0]  s_pixel_id,
    input  wire [31:0]  s_frame_id,
    input  wire [15:0]  s_param_version,
    input  wire         s_sof,
    input  wire         s_eol,
    input  wire         s_eof,
    output wire         m_valid,
    input  wire         m_ready,
    output wire [31:0]  m_p00,
    output wire [31:0]  m_p10,
    output wire [31:0]  m_p01,
    output wire [31:0]  m_p11,
    output wire [15:0]  m_fx,
    output wire [15:0]  m_fy,
    output wire [3:0]   m_neighbor_valid,
    output wire         m_geometry_valid,
    output wire [19:0]  m_pixel_id,
    output wire [31:0]  m_frame_id,
    output wire [15:0]  m_param_version,
    output wire         m_sof,
    output wire         m_eol,
    output wire         m_eof,
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
    localparam integer META_DEPTH = 8;
    reg [1:0] active_slot;
    reg frame_start_fault;
    reg [2:0] wr_ptr, rd_ptr;
    reg [3:0] count;
    reg [1:0] sel00 [0:META_DEPTH-1];
    reg [1:0] sel10 [0:META_DEPTH-1];
    reg [1:0] sel01 [0:META_DEPTH-1];
    reg [1:0] sel11 [0:META_DEPTH-1];
    reg [15:0] fx_mem [0:META_DEPTH-1];
    reg [15:0] fy_mem [0:META_DEPTH-1];
    reg [3:0] mask_mem [0:META_DEPTH-1];
    reg geometry_mem [0:META_DEPTH-1];
    reg [19:0] pixel_id_mem [0:META_DEPTH-1];
    reg [31:0] frame_id_mem [0:META_DEPTH-1];
    reg [15:0] version_mem [0:META_DEPTH-1];
    reg sof_mem [0:META_DEPTH-1];
    reg eol_mem [0:META_DEPTH-1];
    reg eof_mem [0:META_DEPTH-1];

    wire [10:0] base_x = (s_x0 >= IMAGE_WIDTH-1) ? IMAGE_WIDTH-2 : s_x0;
    wire [9:0] base_y = (s_y0 >= IMAGE_HEIGHT-1) ? IMAGE_HEIGHT-2 : s_y0;
    wire [31:0] c00, c10, c01, c11;
    wire cache_lookup_ready, cache_rsp_valid, cache_rsp_ready;
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
    wire cache_invalidate = source_frame_start && count == 0 && adapter_idle;
    wire fifo_space = count < META_DEPTH;
    wire accept = s_valid && s_ready;
    wire response = m_valid && m_ready;

    function automatic [31:0] select_pixel;
        input [1:0] which;
        input [31:0] p00, p10, p01, p11;
        begin
            case (which)
                2'd0: select_pixel = p00;
                2'd1: select_pixel = p10;
                2'd2: select_pixel = p01;
                default: select_pixel = p11;
            endcase
        end
    endfunction

    assign fatal_fault = adapter_fault || frame_start_fault;
    assign s_ready = rstn && fifo_space && cache_lookup_ready &&
                     !source_frame_start && !fatal_fault;
    assign cache_rsp_ready = m_ready && count != 0 && !fatal_fault;
    assign m_valid = cache_rsp_valid && count != 0 && !fatal_fault;
    assign m_p00 = mask_mem[rd_ptr][0] ?
        select_pixel(sel00[rd_ptr], c00, c10, c01, c11) : 32'd0;
    assign m_p10 = mask_mem[rd_ptr][1] ?
        select_pixel(sel10[rd_ptr], c00, c10, c01, c11) : 32'd0;
    assign m_p01 = mask_mem[rd_ptr][2] ?
        select_pixel(sel01[rd_ptr], c00, c10, c01, c11) : 32'd0;
    assign m_p11 = mask_mem[rd_ptr][3] ?
        select_pixel(sel11[rd_ptr], c00, c10, c01, c11) : 32'd0;
    assign m_fx = fx_mem[rd_ptr];
    assign m_fy = fy_mem[rd_ptr];
    assign m_neighbor_valid = mask_mem[rd_ptr];
    assign m_geometry_valid = geometry_mem[rd_ptr] && cache_coord_valid;
    assign m_pixel_id = pixel_id_mem[rd_ptr];
    assign m_frame_id = frame_id_mem[rd_ptr];
    assign m_param_version = version_mem[rd_ptr];
    assign m_sof = sof_mem[rd_ptr];
    assign m_eol = eol_mem[rd_ptr];
    assign m_eof = eof_mem[rd_ptr];
    assign idle = count == 0 && adapter_idle && !cache_rsp_valid;
    assign diagnostic_miss_count = cache_miss_count;
    assign diagnostic_fill_cycles = cache_fill_cycles;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            active_slot <= 2'd0;
            frame_start_fault <= 1'b0;
            wr_ptr <= 3'd0;
            rd_ptr <= 3'd0;
            count <= 4'd0;
        end else begin
            if (source_frame_start) begin
                if (!idle || source_frame_slot >= 2'd3)
                    frame_start_fault <= 1'b1;
                else
                    active_slot <= source_frame_slot;
            end
            if (accept) begin
                sel00[wr_ptr] <= {s_y0 != base_y, s_x0 != base_x};
                sel10[wr_ptr] <= {s_y0 != base_y, s_x1 != base_x};
                sel01[wr_ptr] <= {s_y1 != base_y, s_x0 != base_x};
                sel11[wr_ptr] <= {s_y1 != base_y, s_x1 != base_x};
                fx_mem[wr_ptr] <= s_fx;
                fy_mem[wr_ptr] <= s_fy;
                mask_mem[wr_ptr] <= s_neighbor_valid;
                geometry_mem[wr_ptr] <= s_geometry_valid;
                pixel_id_mem[wr_ptr] <= s_pixel_id;
                frame_id_mem[wr_ptr] <= s_frame_id;
                version_mem[wr_ptr] <= s_param_version;
                sof_mem[wr_ptr] <= s_sof;
                eol_mem[wr_ptr] <= s_eol;
                eof_mem[wr_ptr] <= s_eof;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (response)
                rd_ptr <= rd_ptr + 1'b1;
            case ({accept, response})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

    pixel_tile_cache #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .SET_COUNT(SET_COUNT), .WAYS(WAYS),
        .BANK_READ_LATENCY(BANK_READ_LATENCY)
    ) cache (
        .clk(clk), .rst_n(rstn), .invalidate(cache_invalidate),
        .lookup_valid(accept), .lookup_ready(cache_lookup_ready),
        .lookup_x0({1'b0, base_x}), .lookup_y0({2'b0, base_y}),
        .lookup_rsp_valid(cache_rsp_valid), .lookup_rsp_ready(cache_rsp_ready),
        .pixel_p00(c00), .pixel_p10(c10), .pixel_p01(c01), .pixel_p11(c11),
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
        .fill_data_ready(adapter_data_ready),
        .fill_data(adapter_data), .fill_out_tile_x(adapter_tile_x),
        .fill_out_tile_y(adapter_tile_y),
        .fill_out_row_index(adapter_row), .fill_beat_index(adapter_beat),
        .idle(adapter_idle),
        .first_beat_wait(first_beat_wait),
        .interbeat_wait(interbeat_wait),
        .fatal_fault(adapter_fault),
        .protocol_error_count(read_error_count),
        .completed_rows(fetched_rows),
        .read_response_wait(read_response_wait)
    );
endmodule

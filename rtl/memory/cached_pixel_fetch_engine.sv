`timescale 1ns/1ps

// Streaming cached source-pixel fetch path. Cache hits may be accepted and
// retired on consecutive clocks; a miss holds the single cache transaction
// until all four Tile rows have been filled.
module cached_pixel_fetch_engine #(
    parameter integer IMAGE_WIDTH = 1920,
    parameter integer IMAGE_HEIGHT = 1080,
    parameter integer ADDR_WIDTH = 32,
    parameter integer COORD_WIDTH = 12,
    parameter [ADDR_WIDTH-1:0] FRAME_BASE_BYTE_ADDR = {ADDR_WIDTH{1'b0}}
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire [COORD_WIDTH-1:0]       in_x0,
    input  wire [COORD_WIDTH-1:0]       in_y0,
    input  wire [15:0]                  in_fx,
    input  wire [15:0]                  in_fy,
    input  wire                         in_coord_valid,
    input  wire                         in_sof,
    input  wire                         in_eol,
    output wire [23:0]                  out_pixel,
    output wire                         out_valid,
    output wire                         out_sof,
    output wire                         out_eol,
    input  wire                         rd_cmd_ready,
    output wire                         rd_cmd_en,
    output wire [ADDR_WIDTH-1:0]        rd_cmd_addr,
    output wire [31:0]                  rd_cmd_len,
    input  wire                         rd_data_valid,
    output wire                         rd_data_ready,
    input  wire [255:0]                 rd_data,
    input  wire                         rd_data_last
);
    reg pending_reg;
    reg [15:0] fx_reg;
    reg [15:0] fy_reg;
    reg sof_reg;
    reg eol_reg;

    wire cache_lookup_valid;
    wire cache_lookup_ready;
    wire cache_rsp_valid;
    wire cache_rsp_ready;
    wire [31:0] cache_p00;
    wire [31:0] cache_p10;
    wire [31:0] cache_p01;
    wire [31:0] cache_p11;
    wire cache_hit;
    wire cache_coord_valid;

    wire cache_fill_req_valid;
    wire cache_fill_req_ready;
    wire [COORD_WIDTH-1:0] cache_fill_tile_x;
    wire [COORD_WIDTH-1:0] cache_fill_tile_y;
    wire [1:0] cache_fill_row_index;
    wire reader_fill_data_valid;
    wire reader_fill_data_ready;
    wire [255:0] reader_fill_data;
    wire [11:0] reader_fill_tile_x;
    wire [11:0] reader_fill_tile_y;
    wire [1:0] reader_fill_row_index;
    wire [1:0] reader_fill_beat_index;

    wire response_fire = pending_reg && cache_rsp_valid;
    // A valid coordinate may replace the retired coordinate on the same
    // clock. Invalid/black coordinates are held for the next clock so one
    // bilinear input is never double-booked.
    wire can_accept = !pending_reg || (response_fire && in_coord_valid);
    assign in_ready = rst_n && can_accept
                      && (!in_coord_valid || cache_lookup_ready);
    wire input_fire = in_valid && in_ready;
    wire cached_input_fire = input_fire && in_coord_valid;
    wire black_fire = input_fire && !in_coord_valid;

    assign cache_rsp_ready = pending_reg;
    assign cache_lookup_valid = cached_input_fire;

    wire interp_in_valid = response_fire || black_fire;
    wire interp_coord_valid = response_fire && cache_coord_valid;
    wire [23:0] interp_p00 = response_fire ? cache_p00[31:8] : 24'd0;
    wire [23:0] interp_p10 = response_fire ? cache_p10[31:8] : 24'd0;
    wire [23:0] interp_p01 = response_fire ? cache_p01[31:8] : 24'd0;
    wire [23:0] interp_p11 = response_fire ? cache_p11[31:8] : 24'd0;
    wire [15:0] interp_fx = response_fire ? fx_reg : in_fx;
    wire [15:0] interp_fy = response_fire ? fy_reg : in_fy;
    wire interp_sof = response_fire ? sof_reg : in_sof;
    wire interp_eol = response_fire ? eol_reg : in_eol;

    pixel_tile_cache #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .COORD_WIDTH(COORD_WIDTH),
        .PIXEL_WIDTH(32),
        .SET_COUNT(16),
        .WAYS(8)
    ) tile_cache_inst (
        .clk(clk), .rst_n(rst_n),
        .lookup_valid(cache_lookup_valid), .lookup_ready(cache_lookup_ready),
        .lookup_x0(in_x0), .lookup_y0(in_y0),
        .lookup_rsp_valid(cache_rsp_valid), .lookup_rsp_ready(cache_rsp_ready),
        .pixel_p00(cache_p00), .pixel_p10(cache_p10),
        .pixel_p01(cache_p01), .pixel_p11(cache_p11),
        .cache_hit(cache_hit), .coord_valid(cache_coord_valid),
        .fill_req_valid(cache_fill_req_valid), .fill_req_ready(cache_fill_req_ready),
        .fill_tile_x(cache_fill_tile_x), .fill_tile_y(cache_fill_tile_y),
        .fill_row_index(cache_fill_row_index),
        .fill_data_valid(reader_fill_data_valid), .fill_data_ready(reader_fill_data_ready),
        .fill_data(reader_fill_data), .fill_data_row_index(reader_fill_row_index),
        .fill_data_beat_index(reader_fill_beat_index)
    );

    ddr_burst_reader #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .ADDR_WIDTH(ADDR_WIDTH), .FRAME_BASE_BYTE_ADDR(FRAME_BASE_BYTE_ADDR)
    ) burst_reader_inst (
        .clk(clk), .rst_n(rst_n),
        .fill_req_valid(cache_fill_req_valid), .fill_req_ready(cache_fill_req_ready),
        .fill_tile_x(cache_fill_tile_x), .fill_tile_y(cache_fill_tile_y),
        .fill_row_index(cache_fill_row_index),
        .rd_cmd_en(rd_cmd_en), .rd_cmd_ready(rd_cmd_ready),
        .rd_cmd_addr(rd_cmd_addr), .rd_cmd_len(rd_cmd_len),
        .rd_data_valid(rd_data_valid), .rd_data_ready(rd_data_ready),
        .rd_data(rd_data), .rd_data_last(rd_data_last),
        .fill_data_valid(reader_fill_data_valid), .fill_data_ready(reader_fill_data_ready),
        .fill_data(reader_fill_data), .fill_out_tile_x(reader_fill_tile_x),
        .fill_out_tile_y(reader_fill_tile_y), .fill_out_row_index(reader_fill_row_index),
        .fill_beat_index(reader_fill_beat_index)
    );

    bilinear_interp bilinear_interp_inst (
        .clk(clk), .rst_n(rst_n),
        .p00(interp_p00), .p10(interp_p10), .p01(interp_p01), .p11(interp_p11),
        .dx(interp_fx), .dy(interp_fy), .coord_valid(interp_coord_valid),
        .in_valid(interp_in_valid), .in_sof(interp_sof), .in_eol(interp_eol),
        .out_pixel(out_pixel), .out_valid(out_valid),
        .out_sof(out_sof), .out_eol(out_eol)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_reg <= 1'b0;
            fx_reg <= 16'd0;
            fy_reg <= 16'd0;
            sof_reg <= 1'b0;
            eol_reg <= 1'b0;
        end else begin
            if (cached_input_fire) begin
                fx_reg <= in_fx;
                fy_reg <= in_fy;
                sof_reg <= in_sof;
                eol_reg <= in_eol;
            end
            if (response_fire)
                pending_reg <= cached_input_fire;
            else if (cached_input_fire)
                pending_reg <= 1'b1;
        end
    end
endmodule

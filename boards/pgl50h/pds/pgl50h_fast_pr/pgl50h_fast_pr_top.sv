`timescale 1ns/1ps

// Lightweight 720p30 algorithm-only top for fast P&R experiments.
// The board DDR3/HDMI/frame-capture logic is intentionally outside this top.
module pgl50h_fast_pr_top #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer COORD_WIDTH = 13
) (
    input  wire                         clk,
    input  wire                         reset_n,
    input  wire                         frame_start,
    output wire                         frame_busy,
    output wire                         frame_done,

    output wire [23:0]                  out_pixel,
    output wire                         out_valid,
    output wire                         out_sof,
    output wire                         out_eol
);
    wire                         legacy_mem_req_valid;
    wire [31:0]                  legacy_mem_req_addr;
    wire                         legacy_mem_rsp_ready;
    wire                         cache_rd_cmd_en;
    wire [31:0]                  cache_rd_cmd_addr;
    wire [31:0]                  cache_rd_cmd_len;
    wire                         cache_rd_data_ready;

    // The fast-P&R top has no physical DDR pins.  A board-level DDR3 adapter
    // is connected in the real board top; these constants keep the cache
    // interface internal and prevent 256-bit DDR data from becoming top IO.
    wire                         cache_rd_cmd_ready = 1'b1;
    wire                         cache_rd_data_valid = 1'b0;
    wire [255:0]                 cache_rd_data = 256'd0;
    wire                         cache_rd_data_last = 1'b0;

    localparam signed [31:0] FX_Q19      = 32'sd314572800;
    localparam signed [31:0] FY_Q19      = 32'sd314572800;
    localparam signed [31:0] CX_Q19      = 32'sd335282176;
    localparam signed [31:0] CY_Q19      = 32'sd188481536;
    localparam signed [31:0] INV_FX_Q30  = 32'sd1789569;
    localparam signed [31:0] INV_FY_Q30  = 32'sd1789569;

    mes50hp_top #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .COORD_WIDTH(COORD_WIDTH),
        .ADDR_WIDTH(32),
        .USE_TILE_CACHE(1),
        .TILE_CACHE_SET_COUNT(16),
        .TILE_CACHE_WAYS(4),
        .USE_PSEUDO_LRU(1),
        .FRAME_BASE_BYTE_ADDR(32'h0000_0000)
    ) u_mes50hp_top (
        .clk(clk),
        .reset_n(reset_n),
        .frame_start(frame_start),
        .frame_busy(frame_busy),
        .frame_done(frame_done),
        .cfg_fx_q19(FX_Q19),
        .cfg_fy_q19(FY_Q19),
        .cfg_cx_q19(CX_Q19),
        .cfg_cy_q19(CY_Q19),
        .cfg_inv_fx_q30(INV_FX_Q30),
        .cfg_inv_fy_q30(INV_FY_Q30),
        .cfg_k1_q28(32'sd0),
        .cfg_k2_q28(32'sd0),
        .cfg_p1_q28(32'sd0),
        .cfg_p2_q28(32'sd0),
        .mem_req_valid(legacy_mem_req_valid),
        .mem_req_ready(1'b0),
        .mem_req_addr(legacy_mem_req_addr),
        .mem_rsp_valid(1'b0),
        .mem_rsp_ready(legacy_mem_rsp_ready),
        .mem_rsp_data(24'h00_00_00),
        .cache_rd_cmd_en(cache_rd_cmd_en),
        .cache_rd_cmd_ready(cache_rd_cmd_ready),
        .cache_rd_cmd_addr(cache_rd_cmd_addr),
        .cache_rd_cmd_len(cache_rd_cmd_len),
        .cache_rd_data_valid(cache_rd_data_valid),
        .cache_rd_data_ready(cache_rd_data_ready),
        .cache_rd_data(cache_rd_data),
        .cache_rd_data_last(cache_rd_data_last),
        .out_pixel(out_pixel),
        .out_valid(out_valid),
        .out_sof(out_sof),
        .out_eol(out_eol)
    );
endmodule

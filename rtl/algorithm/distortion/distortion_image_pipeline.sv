`timescale 1ns/1ps

// Functional image pipeline for board-independent verification:
// coordinate_gen -> distortion_core -> pixel fetch -> bilinear_interp.
//
// The current Pixel Fetch engine handles one coordinate transaction at a
// time.  This wrapper therefore uses one in-flight coordinate slot and one
// result holding register so the non-stallable distortion pipeline cannot
// lose its output while Pixel Fetch is busy.  USE_TILE_CACHE selects the
// RGBX8888 burst path while preserving the legacy logical-pixel interface.
module distortion_image_pipeline #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer COORD_WIDTH = 13,
    parameter integer ADDR_WIDTH = 32,
    parameter integer USE_OPTIMIZED_CORE = 0,
    parameter integer USE_TILE_CACHE = 0,
    parameter integer TILE_CACHE_SET_COUNT = 16,
    parameter integer TILE_CACHE_WAYS = 8,
    parameter integer USE_PSEUDO_LRU = 0,
    parameter [ADDR_WIDTH-1:0] FRAME_BASE_BYTE_ADDR = {ADDR_WIDTH{1'b0}}
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         frame_start,
    input  wire                         in_valid,
    input  wire                         in_sof,
    input  wire                         in_eol,
    output wire                         in_ready,
    input  wire signed [31:0]           cfg_fx_q19,
    input  wire signed [31:0]           cfg_fy_q19,
    input  wire signed [31:0]           cfg_cx_q19,
    input  wire signed [31:0]           cfg_cy_q19,
    input  wire signed [31:0]           cfg_inv_fx_q30,
    input  wire signed [31:0]           cfg_inv_fy_q30,
    input  wire signed [31:0]           cfg_k1_q28,
    input  wire signed [31:0]           cfg_k2_q28,
    input  wire signed [31:0]           cfg_p1_q28,
    input  wire signed [31:0]           cfg_p2_q28,
    output wire                         req_valid,
    input  wire                         req_ready,
    output wire [ADDR_WIDTH-1:0]        req_addr,
    input  wire                         rsp_valid,
    output wire                         rsp_ready,
    input  wire [23:0]                  rsp_data,
    output wire [23:0]                  out_pixel,
    output wire                         out_valid,
    output wire                         out_sof,
    output wire                         out_eol,

    output wire                         cache_rd_cmd_en,
    input  wire                         cache_rd_cmd_ready,
    output wire [ADDR_WIDTH-1:0]        cache_rd_cmd_addr,
    output wire [31:0]                  cache_rd_cmd_len,
    input  wire                         cache_rd_data_valid,
    output wire                         cache_rd_data_ready,
    input  wire [255:0]                 cache_rd_data,
    input  wire                         cache_rd_data_last
);

    wire coordinate_fifo_in_ready;
    wire coordinate_fifo_reserve_ready;
    wire coordinate_fifo_out_valid;
    wire coordinate_fifo_out_ready;
    wire [COORD_WIDTH-1:0] coordinate_fifo_out_x0;
    wire [COORD_WIDTH-1:0] coordinate_fifo_out_y0;
    wire [15:0] coordinate_fifo_out_dx;
    wire [15:0] coordinate_fifo_out_dy;
    wire coordinate_fifo_out_coord_valid;
    wire coordinate_fifo_out_sof;
    wire coordinate_fifo_out_eol;

    wire geometry_rst_n;
    wire fifo_rst_n;
    wire fetch_control_rst_n;
    wire fetch_storage_rst_n;
    wire reset_tree_ready;
    // The optimized core contains a wide arithmetic pipeline.  Resetting
    // that data path (or conditionally holding it during reset) creates a
    // multi-thousand-load reset/clock-enable net that PGL50H cannot route
    // reliably.  Keep the core clocking, flush its fixed 15-cycle latency
    // with invalid transactions, and do not accept a new frame until then.
    localparam integer CORE_FLUSH_CYCLES = 16;
    reg [CORE_FLUSH_CYCLES-1:0] core_flush_shift;
    wire core_flush_ready;

    algorithm_reset_tree reset_tree_inst (
        .clk(clk),
        .reset_n(rst_n),
        .geometry_rst_n(geometry_rst_n),
        .fifo_rst_n(fifo_rst_n),
        .fetch_control_rst_n(fetch_control_rst_n),
        .fetch_storage_rst_n(fetch_storage_rst_n),
        .all_ready(reset_tree_ready)
    );

    always @(posedge clk or negedge geometry_rst_n) begin
        if (!geometry_rst_n)
            core_flush_shift <= {CORE_FLUSH_CYCLES{1'b0}};
        else
            core_flush_shift <= {core_flush_shift[CORE_FLUSH_CYCLES-2:0], 1'b1};
    end

    assign core_flush_ready = core_flush_shift[CORE_FLUSH_CYCLES-1];

    wire input_accept = in_valid && in_ready;
    // distortion_core_optimized has a fixed, non-backpressured pipeline.
    // A 32-entry reserve protects its in-flight results while the FIFO is
    // full behind a cache miss; the 544-entry allocation leaves 512 usable
    // coordinate slots to the scanner.
    assign in_ready = reset_tree_ready && core_flush_ready
                      && coordinate_fifo_reserve_ready;

    wire [COORD_WIDTH-1:0] generated_u;
    wire [COORD_WIDTH-1:0] generated_v;
    wire generated_valid;
    wire generated_sof;
    wire generated_eol;

    wire signed [63:0] distortion_src_x_q19;
    wire signed [63:0] distortion_src_y_q19;
    wire signed [31:0] distortion_x0;
    wire signed [31:0] distortion_y0;
    wire [15:0] distortion_dx;
    wire [15:0] distortion_dy;
    wire distortion_coord_valid;
    wire distortion_valid;
    wire distortion_sof;
    wire distortion_eol;
    wire fetch_in_ready;
    wire [23:0] fetch_out_pixel;
    wire fetch_out_valid;
    wire fetch_out_sof;
    wire fetch_out_eol;

    coordinate_gen #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .COORD_WIDTH(COORD_WIDTH)
    ) coordinate_gen_inst (
        .clk(clk),
        .rst_n(geometry_rst_n),
        .in_valid(input_accept),
        .in_sof(in_sof),
        .in_eol(in_eol),
        .out_u(generated_u),
        .out_v(generated_v),
        .out_valid(generated_valid),
        .out_sof(generated_sof),
        .out_eol(generated_eol)
    );

    generate
        if (USE_OPTIMIZED_CORE != 0) begin : generate_optimized_core
            distortion_core_optimized #(
                .IMAGE_WIDTH(IMAGE_WIDTH),
                .IMAGE_HEIGHT(IMAGE_HEIGHT),
                .COORD_WIDTH(COORD_WIDTH)
            ) distortion_core_inst (
                .clk(clk),
                // Reset is implemented at this wrapper boundary.  Tying the
                // arithmetic core high prevents geometry_rst_n from becoming
                // a high-fanout CE on every payload register.
                .rst_n(1'b1),
                .in_u(generated_u),
                .in_v(generated_v),
                .in_valid(generated_valid),
                .in_sof(generated_sof),
                .in_eol(generated_eol),
                .cfg_fx_q19(cfg_fx_q19),
                .cfg_fy_q19(cfg_fy_q19),
                .cfg_cx_q19(cfg_cx_q19),
                .cfg_cy_q19(cfg_cy_q19),
                .cfg_inv_fx_q30(cfg_inv_fx_q30),
                .cfg_inv_fy_q30(cfg_inv_fy_q30),
                .cfg_k1_q28(cfg_k1_q28),
                .cfg_k2_q28(cfg_k2_q28),
                .cfg_p1_q28(cfg_p1_q28),
                .cfg_p2_q28(cfg_p2_q28),
                .out_src_x_q19(distortion_src_x_q19),
                .out_src_y_q19(distortion_src_y_q19),
                .out_x0(distortion_x0),
                .out_y0(distortion_y0),
                .out_dx_q16(distortion_dx),
                .out_dy_q16(distortion_dy),
                .out_coord_valid(distortion_coord_valid),
                .out_valid(distortion_valid),
                .out_sof(distortion_sof),
                .out_eol(distortion_eol)
            );
        end else begin : generate_baseline_core
            distortion_core #(
                .IMAGE_WIDTH(IMAGE_WIDTH),
                .IMAGE_HEIGHT(IMAGE_HEIGHT),
                .COORD_WIDTH(COORD_WIDTH)
            ) distortion_core_inst (
                .clk(clk),
                .rst_n(1'b1),
                .in_u(generated_u),
                .in_v(generated_v),
                .in_valid(generated_valid),
                .in_sof(generated_sof),
                .in_eol(generated_eol),
                .cfg_fx_q19(cfg_fx_q19),
                .cfg_fy_q19(cfg_fy_q19),
                .cfg_cx_q19(cfg_cx_q19),
                .cfg_cy_q19(cfg_cy_q19),
                .cfg_inv_fx_q30(cfg_inv_fx_q30),
                .cfg_inv_fy_q30(cfg_inv_fy_q30),
                .cfg_k1_q28(cfg_k1_q28),
                .cfg_k2_q28(cfg_k2_q28),
                .cfg_p1_q28(cfg_p1_q28),
                .cfg_p2_q28(cfg_p2_q28),
                .out_src_x_q19(distortion_src_x_q19),
                .out_src_y_q19(distortion_src_y_q19),
                .out_x0(distortion_x0),
                .out_y0(distortion_y0),
                .out_dx_q16(distortion_dx),
                .out_dy_q16(distortion_dy),
                .out_coord_valid(distortion_coord_valid),
                .out_valid(distortion_valid),
                .out_sof(distortion_sof),
                .out_eol(distortion_eol)
            );
        end
    endgenerate

    generate
        if (USE_TILE_CACHE == 0) begin : generate_legacy_fetch
            pixel_fetch_engine #(
                .FRAME_STRIDE_PIXELS(IMAGE_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH)
            ) pixel_fetch_engine_inst (
                .clk(clk),
                .rst_n(fetch_control_rst_n),
                .in_x0(coordinate_fifo_out_x0),
                .in_y0(coordinate_fifo_out_y0),
                .in_dx_q16(coordinate_fifo_out_dx),
                .in_dy_q16(coordinate_fifo_out_dy),
                .in_coord_valid(coordinate_fifo_out_coord_valid),
                .in_valid(coordinate_fifo_out_valid),
                .in_sof(coordinate_fifo_out_sof),
                .in_eol(coordinate_fifo_out_eol),
                .in_ready(fetch_in_ready),
                .req_valid(req_valid),
                .req_ready(req_ready),
                .req_addr(req_addr),
                .rsp_valid(rsp_valid),
                .rsp_ready(rsp_ready),
                .rsp_data(rsp_data),
                .out_pixel(fetch_out_pixel),
                .out_valid(fetch_out_valid),
                .out_sof(fetch_out_sof),
                .out_eol(fetch_out_eol)
            );

            assign cache_rd_cmd_en = 1'b0;
            assign cache_rd_cmd_addr = {ADDR_WIDTH{1'b0}};
            assign cache_rd_cmd_len = 32'd0;
            assign cache_rd_data_ready = 1'b0;
        end else begin : generate_cached_fetch
            cached_pixel_fetch_engine #(
                .IMAGE_WIDTH(IMAGE_WIDTH),
                .IMAGE_HEIGHT(IMAGE_HEIGHT),
                .ADDR_WIDTH(ADDR_WIDTH),
                .COORD_WIDTH(COORD_WIDTH),
                .TILE_CACHE_SET_COUNT(TILE_CACHE_SET_COUNT),
                .TILE_CACHE_WAYS(TILE_CACHE_WAYS),
                .USE_PSEUDO_LRU(USE_PSEUDO_LRU),
                .FRAME_BASE_BYTE_ADDR(FRAME_BASE_BYTE_ADDR)
            ) cached_pixel_fetch_engine_inst (
                .clk(clk),
                .rst_n(fetch_control_rst_n),
                .storage_rst_n(fetch_storage_rst_n),
                .frame_start(frame_start),
                .in_valid(coordinate_fifo_out_valid),
                .in_ready(fetch_in_ready),
                .in_x0(coordinate_fifo_out_x0),
                .in_y0(coordinate_fifo_out_y0),
                .in_fx(coordinate_fifo_out_dx),
                .in_fy(coordinate_fifo_out_dy),
                .in_coord_valid(coordinate_fifo_out_coord_valid),
                .in_sof(coordinate_fifo_out_sof),
                .in_eol(coordinate_fifo_out_eol),
                .out_pixel(fetch_out_pixel),
                .out_valid(fetch_out_valid),
                .out_sof(fetch_out_sof),
                .out_eol(fetch_out_eol),
                .rd_cmd_en(cache_rd_cmd_en),
                .rd_cmd_ready(cache_rd_cmd_ready),
                .rd_cmd_addr(cache_rd_cmd_addr),
                .rd_cmd_len(cache_rd_cmd_len),
                .rd_data_valid(cache_rd_data_valid),
                .rd_data_ready(cache_rd_data_ready),
                .rd_data(cache_rd_data),
                .rd_data_last(cache_rd_data_last)
            );

            assign req_valid = 1'b0;
            assign req_addr = {ADDR_WIDTH{1'b0}};
            assign rsp_ready = 1'b0;
        end
    endgenerate

    assign out_pixel = fetch_out_pixel;
    assign out_valid = fetch_out_valid;
    assign out_sof = fetch_out_sof;
    assign out_eol = fetch_out_eol;

    assign coordinate_fifo_out_ready = fetch_in_ready;

    coordinate_fifo #(
        .DEPTH(544),
        .RESERVE_SLOTS(32),
        .COORD_WIDTH(COORD_WIDTH),
        .FRAC_WIDTH(16)
    ) coordinate_fifo_inst (
        .clk(clk), .rst_n(fifo_rst_n),
        // Suppress any pre-reset core transaction until the fixed-latency
        // arithmetic pipe has been flushed with invalid cycles.
        .in_valid(distortion_valid && core_flush_ready), .in_ready(coordinate_fifo_in_ready),
        .reserve_ready(coordinate_fifo_reserve_ready),
        .in_x0(distortion_x0[COORD_WIDTH-1:0]),
        .in_y0(distortion_y0[COORD_WIDTH-1:0]),
        .in_fx(distortion_dx), .in_fy(distortion_dy),
        .in_coord_valid(distortion_coord_valid),
        .in_sof(distortion_sof), .in_eol(distortion_eol),
        .out_valid(coordinate_fifo_out_valid), .out_ready(coordinate_fifo_out_ready),
        .out_x0(coordinate_fifo_out_x0), .out_y0(coordinate_fifo_out_y0),
        .out_fx(coordinate_fifo_out_dx), .out_fy(coordinate_fifo_out_dy),
        .out_coord_valid(coordinate_fifo_out_coord_valid),
        .out_sof(coordinate_fifo_out_sof), .out_eol(coordinate_fifo_out_eol)
    );

endmodule

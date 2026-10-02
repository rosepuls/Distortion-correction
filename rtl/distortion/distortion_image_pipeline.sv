`timescale 1ns/1ps

// Functional image pipeline for board-independent verification:
// coordinate_gen -> distortion_core -> pixel_fetch_engine -> bilinear_interp.
//
// The current Pixel Fetch engine handles one coordinate transaction at a
// time.  This wrapper therefore uses one in-flight coordinate slot and one
// result holding register so the non-stallable distortion pipeline cannot
// lose its output while Pixel Fetch is busy.
module distortion_image_pipeline #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer COORD_WIDTH = 13,
    parameter integer ADDR_WIDTH = 32,
    parameter integer USE_OPTIMIZED_CORE = 0
) (
    input  wire                         clk,
    input  wire                         rst_n,
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
    output wire                         out_eol
);

    reg coordinate_in_flight;
    reg coordinate_buffer_valid;
    reg [ADDR_WIDTH-1:0] coordinate_buffer_x0;
    reg [ADDR_WIDTH-1:0] coordinate_buffer_y0;
    reg [15:0] coordinate_buffer_dx;
    reg [15:0] coordinate_buffer_dy;
    reg coordinate_buffer_coord_valid;
    reg coordinate_buffer_sof;
    reg coordinate_buffer_eol;

    wire input_accept = in_valid && in_ready;
    assign in_ready = rst_n && !coordinate_in_flight && !coordinate_buffer_valid;

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

    coordinate_gen #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .COORD_WIDTH(COORD_WIDTH)
    ) coordinate_gen_inst (
        .clk(clk),
        .rst_n(rst_n),
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
                .rst_n(rst_n),
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
                .rst_n(rst_n),
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

    pixel_fetch_engine #(
        .FRAME_STRIDE_PIXELS(IMAGE_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) pixel_fetch_engine_inst (
        .clk(clk),
        .rst_n(rst_n),
        .in_x0(coordinate_buffer_x0),
        .in_y0(coordinate_buffer_y0),
        .in_dx_q16(coordinate_buffer_dx),
        .in_dy_q16(coordinate_buffer_dy),
        .in_coord_valid(coordinate_buffer_coord_valid),
        .in_valid(coordinate_buffer_valid),
        .in_sof(coordinate_buffer_sof),
        .in_eol(coordinate_buffer_eol),
        .in_ready(fetch_in_ready),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_addr(req_addr),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),
        .rsp_data(rsp_data),
        .out_pixel(out_pixel),
        .out_valid(out_valid),
        .out_sof(out_sof),
        .out_eol(out_eol)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            coordinate_in_flight <= 1'b0;
            coordinate_buffer_valid <= 1'b0;
            coordinate_buffer_x0 <= {ADDR_WIDTH{1'b0}};
            coordinate_buffer_y0 <= {ADDR_WIDTH{1'b0}};
            coordinate_buffer_dx <= 16'd0;
            coordinate_buffer_dy <= 16'd0;
            coordinate_buffer_coord_valid <= 1'b0;
            coordinate_buffer_sof <= 1'b0;
            coordinate_buffer_eol <= 1'b0;
        end else begin
            if (input_accept)
                coordinate_in_flight <= 1'b1;
            if (distortion_valid)
                coordinate_in_flight <= 1'b0;

            if (coordinate_buffer_valid && fetch_in_ready)
                coordinate_buffer_valid <= 1'b0;
            if (distortion_valid) begin
                coordinate_buffer_valid <= 1'b1;
                coordinate_buffer_x0 <= distortion_x0[ADDR_WIDTH-1:0];
                coordinate_buffer_y0 <= distortion_y0[ADDR_WIDTH-1:0];
                coordinate_buffer_dx <= distortion_dx;
                coordinate_buffer_dy <= distortion_dy;
                coordinate_buffer_coord_valid <= distortion_coord_valid;
                coordinate_buffer_sof <= distortion_sof;
                coordinate_buffer_eol <= distortion_eol;
            end
        end
    end

endmodule

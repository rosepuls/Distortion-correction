`timescale 1ns / 1ps

// Complete board-independent Stage 4 demonstration chain:
// radial mapper -> coordinate FIFO -> 2x2 planner -> procedural source -> RGBX interpolator.
module stage4_demo_pipeline #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer FIFO_DEPTH = 16,
    parameter integer LEVEL_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH + 1),
    parameter integer BORDER_REPLICATE = 0
) (
    input  wire                   clk,
    input  wire                   rstn,
    input  wire                   s_valid,
    output wire                   s_ready,
    input  wire [10:0]            s_u,
    input  wire [9:0]             s_v,
    input  wire [19:0]            s_pixel_id,
    input  wire [31:0]            s_frame_id,
    input  wire [15:0]            s_param_version,
    input  wire                   s_sof,
    input  wire                   s_eol,
    input  wire                   s_eof,
    output wire                   m_valid,
    input  wire                   m_ready,
    output wire [31:0]            m_pixel,
    output wire                   m_geometry_valid,
    output wire [19:0]            m_pixel_id,
    output wire [31:0]            m_frame_id,
    output wire [15:0]            m_param_version,
    output wire                   m_sof,
    output wire                   m_eol,
    output wire                   m_eof,
    output wire [LEVEL_WIDTH-1:0] fifo_level
);
    wire map_valid, map_ready, map_geometry_valid, map_j_valid;
    wire signed [31:0] map_sx, map_sy, map_j00, map_j01, map_j10, map_j11;
    wire [19:0] map_pixel_id; wire [31:0] map_frame_id; wire [15:0] map_param_version;
    wire map_sof, map_eol, map_eof;

    demo_radial_mapper #(
        .CENTER_X(IMAGE_WIDTH/2), .CENTER_Y(IMAGE_HEIGHT/2)
    ) mapper (
        .clk(clk),.rstn(rstn),.s_valid(s_valid),.s_ready(s_ready),.s_u(s_u),.s_v(s_v),
        .s_pixel_id(s_pixel_id),.s_frame_id(s_frame_id),.s_param_version(s_param_version),
        .s_sof(s_sof),.s_eol(s_eol),.s_eof(s_eof),
        .m_valid(map_valid),.m_ready(map_ready),.m_sx(map_sx),.m_sy(map_sy),
        .m_geometry_valid(map_geometry_valid),.m_j00(map_j00),.m_j01(map_j01),
        .m_j10(map_j10),.m_j11(map_j11),.m_j_valid(map_j_valid),
        .m_pixel_id(map_pixel_id),.m_frame_id(map_frame_id),
        .m_param_version(map_param_version),.m_sof(map_sof),.m_eol(map_eol),.m_eof(map_eof)
    );

    wire fifo_valid, fifo_ready, fifo_geometry_valid, fifo_j_valid;
    wire signed [31:0] fifo_sx, fifo_sy, fifo_j00, fifo_j01, fifo_j10, fifo_j11;
    wire [19:0] fifo_pixel_id; wire [31:0] fifo_frame_id; wire [15:0] fifo_param_version;
    wire fifo_sof, fifo_eol, fifo_eof;
    coordinate_fifo #(.DEPTH(FIFO_DEPTH),.LEVEL_WIDTH(LEVEL_WIDTH)) queue (
        .clk(clk),.rstn(rstn),.s_valid(map_valid),.s_ready(map_ready),
        .s_sx(map_sx),.s_sy(map_sy),.s_geometry_valid(map_geometry_valid),
        .s_j00(map_j00),.s_j01(map_j01),.s_j10(map_j10),.s_j11(map_j11),.s_j_valid(map_j_valid),
        .s_pixel_id(map_pixel_id),.s_frame_id(map_frame_id),.s_param_version(map_param_version),
        .s_sof(map_sof),.s_eol(map_eol),.s_eof(map_eof),
        .m_valid(fifo_valid),.m_ready(fifo_ready),.m_sx(fifo_sx),.m_sy(fifo_sy),
        .m_geometry_valid(fifo_geometry_valid),.m_j00(fifo_j00),.m_j01(fifo_j01),
        .m_j10(fifo_j10),.m_j11(fifo_j11),.m_j_valid(fifo_j_valid),
        .m_pixel_id(fifo_pixel_id),.m_frame_id(fifo_frame_id),
        .m_param_version(fifo_param_version),.m_sof(fifo_sof),.m_eol(fifo_eol),
        .m_eof(fifo_eof),.level(fifo_level)
    );

    wire plan_valid, plan_ready, plan_geometry_valid;
    wire [10:0] plan_x0, plan_x1; wire [9:0] plan_y0, plan_y1;
    wire [15:0] plan_fx, plan_fy; wire [3:0] plan_neighbor_valid;
    wire [19:0] plan_pixel_id; wire [31:0] plan_frame_id; wire [15:0] plan_param_version;
    wire plan_sof, plan_eol, plan_eof;
    bilinear_sample_planner #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT)) planner (
        .clk(clk),.rstn(rstn),.s_valid(fifo_valid),.s_ready(fifo_ready),
        .s_sx(fifo_sx),.s_sy(fifo_sy),.s_geometry_valid(fifo_geometry_valid),
        .s_border_replicate(BORDER_REPLICATE != 0),
        .s_pixel_id(fifo_pixel_id),.s_frame_id(fifo_frame_id),
        .s_param_version(fifo_param_version),.s_sof(fifo_sof),.s_eol(fifo_eol),.s_eof(fifo_eof),
        .m_valid(plan_valid),.m_ready(plan_ready),.m_x0(plan_x0),.m_x1(plan_x1),
        .m_y0(plan_y0),.m_y1(plan_y1),.m_fx(plan_fx),.m_fy(plan_fy),
        .m_neighbor_valid(plan_neighbor_valid),.m_geometry_valid(plan_geometry_valid),
        .m_pixel_id(plan_pixel_id),.m_frame_id(plan_frame_id),
        .m_param_version(plan_param_version),.m_sof(plan_sof),.m_eol(plan_eol),.m_eof(plan_eof)
    );

    wire read_valid, read_ready, read_geometry_valid;
    wire [31:0] read_p00, read_p10, read_p01, read_p11;
    wire [15:0] read_fx, read_fy; wire [3:0] read_neighbor_valid;
    wire [19:0] read_pixel_id; wire [31:0] read_frame_id; wire [15:0] read_param_version;
    wire read_sof, read_eol, read_eof;
    procedural_pixel_reader #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT)) reader (
        .clk(clk),.rstn(rstn),.s_valid(plan_valid),.s_ready(plan_ready),
        .s_x0(plan_x0),.s_x1(plan_x1),.s_y0(plan_y0),.s_y1(plan_y1),
        .s_fx(plan_fx),.s_fy(plan_fy),.s_neighbor_valid(plan_neighbor_valid),
        .s_geometry_valid(plan_geometry_valid),.s_pixel_id(plan_pixel_id),
        .s_frame_id(plan_frame_id),.s_param_version(plan_param_version),
        .s_sof(plan_sof),.s_eol(plan_eol),.s_eof(plan_eof),
        .m_valid(read_valid),.m_ready(read_ready),.m_p00(read_p00),.m_p10(read_p10),
        .m_p01(read_p01),.m_p11(read_p11),.m_fx(read_fx),.m_fy(read_fy),
        .m_neighbor_valid(read_neighbor_valid),.m_geometry_valid(read_geometry_valid),
        .m_pixel_id(read_pixel_id),.m_frame_id(read_frame_id),
        .m_param_version(read_param_version),.m_sof(read_sof),.m_eol(read_eol),.m_eof(read_eof)
    );

    bilinear_interpolator interpolator (
        .clk(clk),.rstn(rstn),.s_valid(read_valid),.s_ready(read_ready),
        .s_p00(read_p00),.s_p10(read_p10),.s_p01(read_p01),.s_p11(read_p11),
        .s_fx(read_fx),.s_fy(read_fy),.s_neighbor_valid(read_neighbor_valid),
        .s_geometry_valid(read_geometry_valid),.s_pixel_id(read_pixel_id),
        .s_frame_id(read_frame_id),.s_param_version(read_param_version),
        .s_sof(read_sof),.s_eol(read_eol),.s_eof(read_eof),
        .m_valid(m_valid),.m_ready(m_ready),.m_pixel(m_pixel),
        .m_geometry_valid(m_geometry_valid),.m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id),.m_param_version(m_param_version),
        .m_sof(m_sof),.m_eol(m_eol),.m_eof(m_eof)
    );
endmodule

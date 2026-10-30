`timescale 1ns / 1ps

// DDR-backed identity path for processing one leased input frame. The caller
// starts the source frame only after the previous request/response stream has
// drained; its output must be written to an independently leased output slot.
module stage5_identity_pipeline #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer FIFO_DEPTH = 16,
    parameter integer LEVEL_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH + 1),
    parameter integer CACHE_SET_COUNT = 16,
    parameter integer CACHE_WAYS = 4,
    parameter integer RADIAL_MAPPING = 0,
    parameter integer RADIAL_DENOM_SHIFT = 23
) (
    input  wire                   clk,
    input  wire                   rstn,
    input  wire                   source_frame_start,
    input  wire [1:0]             source_frame_slot,
    input  wire                   s_valid,
    output wire                   s_ready,
    input  wire [10:0]            s_u,
    input  wire [9:0]             s_v,
    input  wire [19:0]            s_pixel_id,
    input  wire [31:0]            s_frame_id,
    input  wire [15:0]            s_param_version,
    input  wire [287:0]           homography_words,
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
    output wire                   read_valid,
    output wire [27:0]            read_addr,
    output wire [3:0]             read_len,
    output wire                   read_reserve,
    input  wire                   read_ready,
    input  wire                   read_rvalid,
    input  wire [255:0]           read_rdata,
    input  wire                   read_rlast,
    output wire                   reader_idle,
    output wire                   reader_fault,
    output wire [15:0]            read_error_count,
    output wire [31:0]            fetched_rows,
    output wire [23:0]            diagnostic_miss_count,
    output wire [23:0]            diagnostic_fill_cycles,
    output wire                   read_response_wait,
    output wire                   first_beat_wait,
    output wire                   interbeat_wait,
    output wire [LEVEL_WIDTH-1:0] fifo_level
);
    wire coord_valid, coord_ready;
    wire coord_geometry_valid /* synthesis PAP_MARK_DEBUG="true" */;
    wire coord_j_valid;
    wire signed [31:0] sx /* synthesis PAP_MARK_DEBUG="true" */;
    wire signed [31:0] sy /* synthesis PAP_MARK_DEBUG="true" */;
    wire signed [31:0] j00, j01, j10, j11;
    wire [19:0] coord_pixel_id /* synthesis PAP_MARK_DEBUG="true" */;
    wire [31:0] coord_frame_id;
    wire [15:0] coord_version;
    wire coord_sof, coord_eol, coord_eof;
    identity_coordinate_pipeline #(
        .FIFO_DEPTH(FIFO_DEPTH), .LEVEL_WIDTH(LEVEL_WIDTH),
        .RADIAL_MAPPING(RADIAL_MAPPING),
        .CENTER_X(IMAGE_WIDTH/2), .CENTER_Y(IMAGE_HEIGHT/2),
        .RADIAL_DENOM_SHIFT(RADIAL_DENOM_SHIFT)
    ) coordinates (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_u(s_u), .s_v(s_v), .s_pixel_id(s_pixel_id),
        .s_frame_id(s_frame_id), .s_param_version(s_param_version),
        .homography_words(homography_words),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(coord_valid), .m_ready(coord_ready),
        .m_sx(sx), .m_sy(sy), .m_geometry_valid(coord_geometry_valid),
        .m_j00(j00), .m_j01(j01), .m_j10(j10), .m_j11(j11),
        .m_j_valid(coord_j_valid), .m_pixel_id(coord_pixel_id),
        .m_frame_id(coord_frame_id), .m_param_version(coord_version),
        .m_sof(coord_sof), .m_eol(coord_eol), .m_eof(coord_eof),
        .fifo_level(fifo_level)
    );

    wire plan_valid, plan_ready;
    wire plan_geometry_valid /* synthesis PAP_MARK_DEBUG="true" */;
    wire [10:0] x0, x1;
    wire [9:0] y0, y1;
    wire [15:0] plan_fx, plan_fy;
    wire [3:0] plan_mask /* synthesis PAP_MARK_DEBUG="true" */;
    wire [19:0] plan_pixel_id;
    wire [31:0] plan_frame_id;
    wire [15:0] plan_version;
    wire plan_sof, plan_eol, plan_eof;
    bilinear_sample_planner #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .STRICT_BLACK_BORDER(RADIAL_MAPPING == 2)
    ) planner (
        .clk(clk), .rstn(rstn), .s_valid(coord_valid), .s_ready(coord_ready),
        .s_sx(sx), .s_sy(sy), .s_geometry_valid(coord_geometry_valid),
        .s_border_replicate(RADIAL_MAPPING == 0), .s_pixel_id(coord_pixel_id),
        .s_frame_id(coord_frame_id), .s_param_version(coord_version),
        .s_sof(coord_sof), .s_eol(coord_eol), .s_eof(coord_eof),
        .m_valid(plan_valid), .m_ready(plan_ready),
        .m_x0(x0), .m_x1(x1), .m_y0(y0), .m_y1(y1),
        .m_fx(plan_fx), .m_fy(plan_fy),
        .m_neighbor_valid(plan_mask),
        .m_geometry_valid(plan_geometry_valid),
        .m_pixel_id(plan_pixel_id), .m_frame_id(plan_frame_id),
        .m_param_version(plan_version),
        .m_sof(plan_sof), .m_eol(plan_eol), .m_eof(plan_eof)
    );

    wire pixels_valid, pixels_ready;
    wire pixels_geometry_valid /* synthesis PAP_MARK_DEBUG="true" */;
    wire [31:0] p00, p10, p01, p11;
    wire [15:0] pixels_fx, pixels_fy;
    wire [3:0] pixels_mask /* synthesis PAP_MARK_DEBUG="true" */;
    wire [19:0] pixels_id /* synthesis PAP_MARK_DEBUG="true" */;
    wire [31:0] pixels_frame;
    wire [15:0] pixels_version;
    wire pixels_sof, pixels_eol, pixels_eof;
    cached_neighbor_reader #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .SET_COUNT(CACHE_SET_COUNT), .WAYS(CACHE_WAYS)
    ) reader (
        .clk(clk), .rstn(rstn),
        .source_frame_start(source_frame_start),
        .source_frame_slot(source_frame_slot),
        .s_valid(plan_valid), .s_ready(plan_ready),
        .s_x0(x0), .s_x1(x1), .s_y0(y0), .s_y1(y1),
        .s_fx(plan_fx), .s_fy(plan_fy),
        .s_neighbor_valid(plan_mask),
        .s_geometry_valid(plan_geometry_valid),
        .s_pixel_id(plan_pixel_id), .s_frame_id(plan_frame_id),
        .s_param_version(plan_version),
        .s_sof(plan_sof), .s_eol(plan_eol), .s_eof(plan_eof),
        .m_valid(pixels_valid), .m_ready(pixels_ready),
        .m_p00(p00), .m_p10(p10), .m_p01(p01), .m_p11(p11),
        .m_fx(pixels_fx), .m_fy(pixels_fy),
        .m_neighbor_valid(pixels_mask),
        .m_geometry_valid(pixels_geometry_valid),
        .m_pixel_id(pixels_id), .m_frame_id(pixels_frame),
        .m_param_version(pixels_version),
        .m_sof(pixels_sof), .m_eol(pixels_eol), .m_eof(pixels_eof),
        .read_valid(read_valid), .read_addr(read_addr),
        .read_len(read_len), .read_reserve(read_reserve),
        .read_ready(read_ready), .read_rvalid(read_rvalid),
        .read_rdata(read_rdata), .read_rlast(read_rlast),
        .idle(reader_idle), .fatal_fault(reader_fault),
        .read_error_count(read_error_count), .fetched_rows(fetched_rows),
        .diagnostic_miss_count(diagnostic_miss_count),
        .diagnostic_fill_cycles(diagnostic_fill_cycles),
        .read_response_wait(read_response_wait),
        .first_beat_wait(first_beat_wait),
        .interbeat_wait(interbeat_wait)
    );

    pipelined_bilinear_interpolator interpolator (
        .clk(clk), .rstn(rstn),
        .s_valid(pixels_valid), .s_ready(pixels_ready),
        .s_p00(p00), .s_p10(p10), .s_p01(p01), .s_p11(p11),
        .s_fx(pixels_fx), .s_fy(pixels_fy),
        .s_neighbor_valid(pixels_mask),
        .s_geometry_valid(pixels_geometry_valid),
        .s_pixel_id(pixels_id), .s_frame_id(pixels_frame),
        .s_param_version(pixels_version),
        .s_sof(pixels_sof), .s_eol(pixels_eol), .s_eof(pixels_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_pixel(m_pixel),
        .m_geometry_valid(m_geometry_valid), .m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id), .m_param_version(m_param_version),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );
endmodule

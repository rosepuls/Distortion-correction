`timescale 1ns / 1ps

module identity_coordinate_pipeline #(
    parameter integer FIFO_DEPTH = 16,
    parameter integer LEVEL_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH + 1),
    parameter integer RADIAL_MAPPING = 0,
    parameter integer SCALE_3_2_OUTPUT = 0,
    parameter integer CENTER_X = 640,
    parameter integer CENTER_Y = 360,
    parameter integer RADIAL_DENOM_SHIFT = 23
) (
    input  wire                       clk,
    input  wire                       rstn,

    input  wire                       s_valid,
    output wire                       s_ready,
    input  wire [10:0]                s_u,
    input  wire [10:0]                s_v,
    input  wire [19:0]                s_pixel_id,
    input  wire [31:0]                s_frame_id,
    input  wire [15:0]                s_param_version,
    input  wire [287:0]               homography_words,
    input  wire                       s_sof,
    input  wire                       s_eol,
    input  wire                       s_eof,

    output wire                       m_valid,
    input  wire                       m_ready,
    output wire signed [31:0]         m_sx,
    output wire signed [31:0]         m_sy,
    output wire                       m_geometry_valid,
    output wire signed [31:0]         m_j00,
    output wire signed [31:0]         m_j01,
    output wire signed [31:0]         m_j10,
    output wire signed [31:0]         m_j11,
    output wire                       m_j_valid,
    output wire [19:0]                m_pixel_id,
    output wire [31:0]                m_frame_id,
    output wire [15:0]                m_param_version,
    output wire                       m_sof,
    output wire                       m_eol,
    output wire                       m_eof,
    output wire [LEVEL_WIDTH-1:0]     fifo_level
);

    wire mapper_valid;
    wire mapper_ready;
    wire signed [31:0] mapper_sx;
    wire signed [31:0] mapper_sy;
    wire mapper_geometry_valid;
    wire signed [31:0] mapper_j00;
    wire signed [31:0] mapper_j01;
    wire signed [31:0] mapper_j10;
    wire signed [31:0] mapper_j11;
    wire mapper_j_valid;
    wire [19:0] mapper_pixel_id;
    wire [31:0] mapper_frame_id;
    wire [15:0] mapper_param_version;
    wire mapper_sof;
    wire mapper_eol;
    wire mapper_eof;

    generate if (RADIAL_MAPPING == 2) begin : angle_and_brown_mapping
    wire angle_valid, angle_ready, angle_geometry_valid;
    wire signed [31:0] angle_sx;
    wire signed [31:0] angle_sy;
    wire [19:0] angle_pixel_id;
    wire [31:0] angle_frame_id;
    wire [15:0] angle_version;
    wire angle_sof, angle_eol, angle_eof;
    wire h_in_valid, h_in_ready;
    wire signed [31:0] h_in_u_q16, h_in_v_q16;
    wire [19:0] h_in_pixel_id;
    wire [31:0] h_in_frame_id;
    wire [15:0] h_in_version;
    wire h_in_sof, h_in_eol, h_in_eof;
    if (SCALE_3_2_OUTPUT != 0) begin : scale_output_coordinates
        wire scale_valid;
        wire signed [31:0] scale_sx, scale_sy;
        wire scale_geometry_valid;
        wire [20:0] scale_pixel_id;
        wire [31:0] scale_frame_id;
        wire [15:0] scale_version;
        wire scale_sof, scale_eol, scale_eof;
        scale_3_2_mapper scale_map (
            .clk(clk), .rstn(rstn),
            .s_valid(s_valid), .s_ready(s_ready), .s_u({1'b0, s_u}),
            .s_v({1'b0, s_v}), .s_pixel_id({1'b0, s_pixel_id}),
            .s_frame_id(s_frame_id), .s_param_version(s_param_version),
            .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
            .m_valid(scale_valid), .m_ready(h_in_ready),
            .m_sx(scale_sx), .m_sy(scale_sy),
            .m_geometry_valid(scale_geometry_valid),
            .m_pixel_id(scale_pixel_id), .m_frame_id(scale_frame_id),
            .m_param_version(scale_version), .m_sof(scale_sof),
            .m_eol(scale_eol), .m_eof(scale_eof)
        );
        assign h_in_valid = scale_valid;
        assign h_in_u_q16 = scale_sx;
        assign h_in_v_q16 = scale_sy;
        assign h_in_pixel_id = scale_pixel_id[19:0];
        assign h_in_frame_id = scale_frame_id;
        assign h_in_version = scale_version;
        assign h_in_sof = scale_sof;
        assign h_in_eol = scale_eol;
        assign h_in_eof = scale_eof;
    end else begin : native_coordinates
        assign h_in_valid = s_valid;
        assign s_ready = h_in_ready;
        assign h_in_u_q16 = $signed({5'd0, s_u, 16'd0});
        assign h_in_v_q16 = $signed({5'd0, s_v, 16'd0});
        assign h_in_pixel_id = s_pixel_id;
        assign h_in_frame_id = s_frame_id;
        assign h_in_version = s_param_version;
        assign h_in_sof = s_sof;
        assign h_in_eol = s_eol;
        assign h_in_eof = s_eof;
    end
    homography_mapper #(.INPUT_Q16(1)) angle (
        .clk(clk), .rstn(rstn), .coefficients(homography_words),
        .s_valid(h_in_valid), .s_ready(h_in_ready), .s_u(11'd0), .s_v(10'd0),
        .s_u_q16(h_in_u_q16), .s_v_q16(h_in_v_q16),
        .s_pixel_id(h_in_pixel_id), .s_frame_id(h_in_frame_id),
        .s_param_version(h_in_version), .s_sof(h_in_sof),
        .s_eol(h_in_eol), .s_eof(h_in_eof),
        .m_valid(angle_valid), .m_ready(angle_ready),
        .m_sx(angle_sx), .m_sy(angle_sy),
        .m_geometry_valid(angle_geometry_valid),
        .m_pixel_id(angle_pixel_id), .m_frame_id(angle_frame_id),
        .m_param_version(angle_version),
        .m_sof(angle_sof), .m_eol(angle_eol), .m_eof(angle_eof)
    );
    fractional_brown_mapper lens (
        .clk(clk), .rstn(rstn), .s_valid(angle_valid), .s_ready(angle_ready),
        .s_sx(angle_sx), .s_sy(angle_sy),
        .s_geometry_valid(angle_geometry_valid),
        .s_pixel_id(angle_pixel_id), .s_frame_id(angle_frame_id),
        .s_param_version(angle_version),
        .s_sof(angle_sof), .s_eol(angle_eol), .s_eof(angle_eof),
        .m_valid(mapper_valid), .m_ready(mapper_ready),
        .m_sx(mapper_sx), .m_sy(mapper_sy),
        .m_geometry_valid(mapper_geometry_valid),
        .m_pixel_id(mapper_pixel_id), .m_frame_id(mapper_frame_id),
        .m_param_version(mapper_param_version),
        .m_sof(mapper_sof), .m_eol(mapper_eol), .m_eof(mapper_eof)
    );
    assign mapper_j00 = 0; assign mapper_j01 = 0;
    assign mapper_j10 = 0; assign mapper_j11 = 0;
    assign mapper_j_valid = 0;
    end else if (RADIAL_MAPPING != 0) begin : radial_mapping
    demo_radial_mapper #(
        .CENTER_X(CENTER_X), .CENTER_Y(CENTER_Y),
        .RADIAL_DENOM_SHIFT(RADIAL_DENOM_SHIFT)
    ) mapper (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_u(s_u), .s_v(s_v), .s_pixel_id(s_pixel_id),
        .s_frame_id(s_frame_id), .s_param_version(s_param_version),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(mapper_valid), .m_ready(mapper_ready),
        .m_sx(mapper_sx), .m_sy(mapper_sy),
        .m_geometry_valid(mapper_geometry_valid),
        .m_j00(mapper_j00), .m_j01(mapper_j01),
        .m_j10(mapper_j10), .m_j11(mapper_j11),
        .m_j_valid(mapper_j_valid), .m_pixel_id(mapper_pixel_id),
        .m_frame_id(mapper_frame_id),
        .m_param_version(mapper_param_version),
        .m_sof(mapper_sof), .m_eol(mapper_eol), .m_eof(mapper_eof)
    );
    end else begin : identity_mapping
    identity_mapper mapper (
        .clk(clk),
        .rstn(rstn),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_u(s_u),
        .s_v(s_v),
        .s_pixel_id(s_pixel_id),
        .s_frame_id(s_frame_id),
        .s_param_version(s_param_version),
        .s_sof(s_sof),
        .s_eol(s_eol),
        .s_eof(s_eof),
        .m_valid(mapper_valid),
        .m_ready(mapper_ready),
        .m_sx(mapper_sx),
        .m_sy(mapper_sy),
        .m_geometry_valid(mapper_geometry_valid),
        .m_j00(mapper_j00),
        .m_j01(mapper_j01),
        .m_j10(mapper_j10),
        .m_j11(mapper_j11),
        .m_j_valid(mapper_j_valid),
        .m_pixel_id(mapper_pixel_id),
        .m_frame_id(mapper_frame_id),
        .m_param_version(mapper_param_version),
        .m_sof(mapper_sof),
        .m_eol(mapper_eol),
        .m_eof(mapper_eof)
    );
    end endgenerate

    coordinate_fifo #(
        .DEPTH(FIFO_DEPTH),
        .LEVEL_WIDTH(LEVEL_WIDTH)
    ) queue (
        .clk(clk),
        .rstn(rstn),
        .s_valid(mapper_valid),
        .s_ready(mapper_ready),
        .s_sx(mapper_sx),
        .s_sy(mapper_sy),
        .s_geometry_valid(mapper_geometry_valid),
        .s_j00(mapper_j00),
        .s_j01(mapper_j01),
        .s_j10(mapper_j10),
        .s_j11(mapper_j11),
        .s_j_valid(mapper_j_valid),
        .s_pixel_id(mapper_pixel_id),
        .s_frame_id(mapper_frame_id),
        .s_param_version(mapper_param_version),
        .s_sof(mapper_sof),
        .s_eol(mapper_eol),
        .s_eof(mapper_eof),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_sx(m_sx),
        .m_sy(m_sy),
        .m_geometry_valid(m_geometry_valid),
        .m_j00(m_j00),
        .m_j01(m_j01),
        .m_j10(m_j10),
        .m_j11(m_j11),
        .m_j_valid(m_j_valid),
        .m_pixel_id(m_pixel_id),
        .m_frame_id(m_frame_id),
        .m_param_version(m_param_version),
        .m_sof(m_sof),
        .m_eol(m_eol),
        .m_eof(m_eof),
        .level(fifo_level)
    );

endmodule

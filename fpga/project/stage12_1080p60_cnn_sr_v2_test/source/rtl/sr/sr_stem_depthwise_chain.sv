`timescale 1ns / 1ps

// Isolated luma-window -> trained stem -> feature halo/window -> block1
// depthwise/pointwise residual block. The skip tap is the feature-window center.
module sr_stem_depthwise_chain #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer X_WIDTH = 11,
    parameter integer Y_WIDTH = 10,
    parameter integer PIXEL_ID_WIDTH = 21,
    parameter integer FRAME_ID_WIDTH = 32
) (
    input  wire                      clk,
    input  wire                      rstn,
    input  wire                      s_valid,
    output wire                      s_ready,
    input  wire [71:0]               s_window,
    input  wire [X_WIDTH-1:0]        s_x,
    input  wire [Y_WIDTH-1:0]        s_y,
    input  wire [PIXEL_ID_WIDTH-1:0] s_pixel_id,
    input  wire [FRAME_ID_WIDTH-1:0] s_frame_id,
    input  wire                      s_sof,
    input  wire                      s_eol,
    input  wire                      s_eof,
    output wire                      m_valid,
    input  wire                      m_ready,
    output wire [63:0]               m_features,
    output wire [X_WIDTH-1:0]        m_x,
    output wire [Y_WIDTH-1:0]        m_y,
    output wire [PIXEL_ID_WIDTH-1:0] m_pixel_id,
    output wire [FRAME_ID_WIDTH-1:0] m_frame_id,
    output wire                      m_sof,
    output wire                      m_eol,
    output wire                      m_eof
);
    wire stem_valid, stem_ready;
    wire [63:0] stem_features;
    wire [X_WIDTH-1:0] stem_x;
    wire [Y_WIDTH-1:0] stem_y;
    wire [PIXEL_ID_WIDTH-1:0] stem_pixel_id;
    wire [FRAME_ID_WIDTH-1:0] stem_frame_id;
    wire stem_sof, stem_eol, stem_eof;

    wire fifo_valid, fifo_ready;
    wire [63:0] fifo_features;
    wire [FRAME_ID_WIDTH-1:0] fifo_frame_id;

    wire window_valid, window_ready;
    wire [575:0] feature_window_data;
    wire [X_WIDTH-1:0] window_x;
    wire [Y_WIDTH-1:0] window_y;
    wire [PIXEL_ID_WIDTH-1:0] window_pixel_id;
    wire [FRAME_ID_WIDTH-1:0] window_frame_id;
    wire window_sof, window_eol, window_eof;
    wire window_fifo_valid, window_fifo_ready;
    wire [575:0] window_fifo_data;
    wire [X_WIDTH-1:0] window_fifo_x;
    wire [Y_WIDTH-1:0] window_fifo_y;
    wire [PIXEL_ID_WIDTH-1:0] window_fifo_pixel_id;
    wire [FRAME_ID_WIDTH-1:0] window_fifo_frame_id;
    wire window_fifo_sof, window_fifo_eol, window_fifo_eof;
    wire depthwise_valid, depthwise_ready;
    wire [63:0] depthwise_features, depthwise_skip;
    wire [X_WIDTH-1:0] depthwise_x;
    wire [Y_WIDTH-1:0] depthwise_y;
    wire [PIXEL_ID_WIDTH-1:0] depthwise_pixel_id;
    wire [FRAME_ID_WIDTH-1:0] depthwise_frame_id;
    wire depthwise_sof, depthwise_eol, depthwise_eof;
    wire pointwise_valid, pointwise_ready;
    wire [63:0] pointwise_features, pointwise_skip;
    wire [X_WIDTH-1:0] pointwise_x;
    wire [Y_WIDTH-1:0] pointwise_y;
    wire [PIXEL_ID_WIDTH-1:0] pointwise_pixel_id;
    wire [FRAME_ID_WIDTH-1:0] pointwise_frame_id;
    wire pointwise_sof, pointwise_eol, pointwise_eof;
    wire result_fifo_valid, result_fifo_ready;
    wire [63:0] result_fifo_features, result_fifo_skip;
    wire [X_WIDTH-1:0] result_fifo_x;
    wire [Y_WIDTH-1:0] result_fifo_y;
    wire [PIXEL_ID_WIDTH-1:0] result_fifo_pixel_id;
    wire [FRAME_ID_WIDTH-1:0] result_fifo_frame_id;
    wire result_fifo_sof, result_fifo_eol, result_fifo_eof;

    sr_stem_conv #(
        .PIXEL_ID_WIDTH(PIXEL_ID_WIDTH), .FRAME_ID_WIDTH(FRAME_ID_WIDTH)
    ) stem (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_window(s_window), .s_x(s_x), .s_y(s_y), .s_pixel_id(s_pixel_id),
        .s_frame_id(s_frame_id), .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(stem_valid), .m_ready(stem_ready), .m_features(stem_features),
        .m_x(stem_x), .m_y(stem_y), .m_pixel_id(stem_pixel_id),
        .m_frame_id(stem_frame_id), .m_sof(stem_sof), .m_eol(stem_eol), .m_eof(stem_eof)
    );

    sr_feature_fifo4 #(.FRAME_ID_WIDTH(FRAME_ID_WIDTH)) feature_fifo (
        .clk(clk), .rstn(rstn), .s_valid(stem_valid), .s_ready(stem_ready),
        .s_features(stem_features), .s_frame_id(stem_frame_id),
        .m_valid(fifo_valid), .m_ready(fifo_ready),
        .m_features(fifo_features), .m_frame_id(fifo_frame_id)
    );

    sr_feature_window_pipeline #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .X_WIDTH(X_WIDTH), .Y_WIDTH(Y_WIDTH), .FRAME_ID_WIDTH(FRAME_ID_WIDTH),
        .X_ADDR_WIDTH((IMAGE_WIDTH+2 <= 2) ? 1 : $clog2(IMAGE_WIDTH+2))
    ) feature_window (
        .clk(clk), .rstn(rstn), .s_valid(fifo_valid), .s_ready(fifo_ready),
        .s_features(fifo_features), .s_frame_id(fifo_frame_id),
        .m_valid(window_valid), .m_ready(window_ready), .m_window(feature_window_data),
        .m_x(window_x), .m_y(window_y), .m_pixel_id(window_pixel_id),
        .m_frame_id(window_frame_id), .m_sof(window_sof),
        .m_eol(window_eol), .m_eof(window_eof)
    );

    sr_window_fifo1 #(
        .X_WIDTH(X_WIDTH), .Y_WIDTH(Y_WIDTH), .PIXEL_ID_WIDTH(PIXEL_ID_WIDTH),
        .FRAME_ID_WIDTH(FRAME_ID_WIDTH)
    ) window_fifo (
        .clk(clk), .rstn(rstn), .s_valid(window_valid), .s_ready(window_ready),
        .s_window(feature_window_data), .s_x(window_x), .s_y(window_y),
        .s_pixel_id(window_pixel_id), .s_frame_id(window_frame_id),
        .s_sof(window_sof), .s_eol(window_eol), .s_eof(window_eof),
        .m_valid(window_fifo_valid), .m_ready(window_fifo_ready),
        .m_window(window_fifo_data), .m_x(window_fifo_x), .m_y(window_fifo_y),
        .m_pixel_id(window_fifo_pixel_id), .m_frame_id(window_fifo_frame_id),
        .m_sof(window_fifo_sof), .m_eol(window_fifo_eol), .m_eof(window_fifo_eof)
    );

    sr_depthwise_conv #(
        .PIXEL_ID_WIDTH(PIXEL_ID_WIDTH), .FRAME_ID_WIDTH(FRAME_ID_WIDTH)
    ) depthwise (
        .clk(clk), .rstn(rstn), .s_valid(window_fifo_valid), .s_ready(window_fifo_ready),
        .s_window(window_fifo_data), .s_x(window_fifo_x), .s_y(window_fifo_y),
        .s_pixel_id(window_fifo_pixel_id), .s_frame_id(window_fifo_frame_id),
        .s_sof(window_fifo_sof), .s_eol(window_fifo_eol), .s_eof(window_fifo_eof),
        .m_valid(depthwise_valid), .m_ready(depthwise_ready), .m_features(depthwise_features), .m_skip(depthwise_skip),
        .m_x(depthwise_x), .m_y(depthwise_y), .m_pixel_id(depthwise_pixel_id), .m_frame_id(depthwise_frame_id),
        .m_sof(depthwise_sof), .m_eol(depthwise_eol), .m_eof(depthwise_eof)
    );

    sr_pointwise_conv #(
        .PIXEL_ID_WIDTH(PIXEL_ID_WIDTH), .FRAME_ID_WIDTH(FRAME_ID_WIDTH)
    ) pointwise (
        .clk(clk), .rstn(rstn), .s_valid(result_fifo_valid), .s_ready(result_fifo_ready),
        .s_features(result_fifo_features), .s_skip(result_fifo_skip), .s_x(result_fifo_x), .s_y(result_fifo_y),
        .s_pixel_id(result_fifo_pixel_id), .s_frame_id(result_fifo_frame_id),
        .s_sof(result_fifo_sof), .s_eol(result_fifo_eol), .s_eof(result_fifo_eof),
        .m_valid(pointwise_valid), .m_ready(pointwise_ready), .m_features(pointwise_features), .m_skip(pointwise_skip),
        .m_x(pointwise_x), .m_y(pointwise_y), .m_pixel_id(pointwise_pixel_id), .m_frame_id(pointwise_frame_id),
        .m_sof(pointwise_sof), .m_eol(pointwise_eol), .m_eof(pointwise_eof)
    );

    sr_feature_result_fifo2 #(
        .X_WIDTH(X_WIDTH), .Y_WIDTH(Y_WIDTH), .PIXEL_ID_WIDTH(PIXEL_ID_WIDTH),
        .FRAME_ID_WIDTH(FRAME_ID_WIDTH)
    ) result_fifo (
        .clk(clk), .rstn(rstn), .s_valid(depthwise_valid), .s_ready(depthwise_ready),
        .s_features(depthwise_features), .s_skip(depthwise_skip),
        .s_x(depthwise_x), .s_y(depthwise_y), .s_pixel_id(depthwise_pixel_id),
        .s_frame_id(depthwise_frame_id), .s_sof(depthwise_sof),
        .s_eol(depthwise_eol), .s_eof(depthwise_eof),
        .m_valid(result_fifo_valid), .m_ready(result_fifo_ready),
        .m_features(result_fifo_features), .m_skip(result_fifo_skip),
        .m_x(result_fifo_x), .m_y(result_fifo_y), .m_pixel_id(result_fifo_pixel_id),
        .m_frame_id(result_fifo_frame_id), .m_sof(result_fifo_sof),
        .m_eol(result_fifo_eol), .m_eof(result_fifo_eof)
    );

    sr_residual_join #(
        .BLOCK_INDEX(0), .PIXEL_ID_WIDTH(PIXEL_ID_WIDTH), .FRAME_ID_WIDTH(FRAME_ID_WIDTH)
    ) residual_join (
        .clk(clk), .rstn(rstn), .s_valid(pointwise_valid), .s_ready(pointwise_ready),
        .s_skip(pointwise_skip), .s_branch(pointwise_features), .s_x(pointwise_x), .s_y(pointwise_y),
        .s_pixel_id(pointwise_pixel_id), .s_frame_id(pointwise_frame_id),
        .s_sof(pointwise_sof), .s_eol(pointwise_eol), .s_eof(pointwise_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_features(m_features),
        .m_x(m_x), .m_y(m_y), .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );
endmodule

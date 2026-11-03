`timescale 1ns / 1ps

// Converts an unpadded 8-channel feature stream into zero-padded 3x3 windows.
module sr_feature_window_pipeline #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer PADDED_WIDTH = IMAGE_WIDTH + 2,
    parameter integer PADDED_HEIGHT = IMAGE_HEIGHT + 2,
    parameter integer X_WIDTH = 11,
    parameter integer Y_WIDTH = 10,
    parameter integer FRAME_ID_WIDTH = 32,
    parameter integer X_ADDR_WIDTH = (PADDED_WIDTH <= 2) ? 1 : $clog2(PADDED_WIDTH)
) (
    input  wire                      clk,
    input  wire                      rstn,
    input  wire                      s_valid,
    output wire                      s_ready,
    input  wire [63:0]               s_features,
    input  wire [FRAME_ID_WIDTH-1:0] s_frame_id,
    output wire                      m_valid,
    input  wire                      m_ready,
    output wire [575:0]              m_window,
    output wire [X_WIDTH-1:0]        m_x,
    output wire [Y_WIDTH-1:0]        m_y,
    output wire [20:0]               m_pixel_id,
    output wire [FRAME_ID_WIDTH-1:0] m_frame_id,
    output wire                      m_sof,
    output wire                      m_eol,
    output wire                      m_eof
);
    wire halo_valid, halo_ready;
    wire [63:0] halo_features;
    wire [X_WIDTH-1:0] halo_x;
    wire [Y_WIDTH-1:0] halo_y;
    wire [FRAME_ID_WIDTH-1:0] halo_frame_id;
    wire halo_sof, halo_eol, halo_eof;

    sr_feature_halo #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PADDED_WIDTH(PADDED_WIDTH), .PADDED_HEIGHT(PADDED_HEIGHT),
        .X_WIDTH(X_WIDTH), .Y_WIDTH(Y_WIDTH)
    ) halo (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_features(s_features), .s_frame_id(s_frame_id),
        .m_valid(halo_valid), .m_ready(halo_ready), .m_features(halo_features),
        .m_x(halo_x), .m_y(halo_y), .m_frame_id(halo_frame_id),
        .m_sof(halo_sof), .m_eol(halo_eol), .m_eof(halo_eof)
    );

    sr_feature_window3x3 #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PADDED_WIDTH(PADDED_WIDTH), .PADDED_HEIGHT(PADDED_HEIGHT),
        .X_WIDTH(X_WIDTH), .Y_WIDTH(Y_WIDTH), .FRAME_ID_WIDTH(FRAME_ID_WIDTH),
        .X_ADDR_WIDTH(X_ADDR_WIDTH)
    ) window3x3 (
        .clk(clk), .rstn(rstn), .s_valid(halo_valid), .s_ready(halo_ready),
        .s_features(halo_features), .s_x(halo_x), .s_y(halo_y),
        .s_frame_id(halo_frame_id), .s_sof(halo_sof), .s_eol(halo_eol), .s_eof(halo_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_window(m_window),
        .m_x(m_x), .m_y(m_y), .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );
endmodule

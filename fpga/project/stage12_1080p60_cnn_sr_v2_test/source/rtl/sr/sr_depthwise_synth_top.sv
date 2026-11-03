`timescale 1ns/1ps
module sr_depthwise_synth_top (
    input wire clk, input wire rstn,
    input wire s_valid, output wire s_ready,
    input wire [575:0] s_window,
    input wire [10:0] s_x, input wire [9:0] s_y,
    input wire [20:0] s_pixel_id, input wire [31:0] s_frame_id,
    input wire s_sof, input wire s_eol, input wire s_eof,
    output wire m_valid, input wire m_ready,
    output wire [63:0] m_features,
    output wire [10:0] m_x, output wire [9:0] m_y,
    output wire [20:0] m_pixel_id, output wire [31:0] m_frame_id,
    output wire m_sof, output wire m_eol, output wire m_eof
);
    sr_depthwise_conv depthwise (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_window(s_window), .s_x(s_x), .s_y(s_y), .s_pixel_id(s_pixel_id),
        .s_frame_id(s_frame_id), .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_features(m_features),
        .m_x(m_x), .m_y(m_y), .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );
endmodule

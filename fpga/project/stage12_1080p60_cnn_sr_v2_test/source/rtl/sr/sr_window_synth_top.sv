`timescale 1ns/1ps
module sr_window_synth_top (
    input wire clk, input wire rstn,
    input wire s_valid, output wire s_ready,
    input wire [7:0] s_luma,
    input wire [10:0] s_x, input wire [9:0] s_y,
    input wire [31:0] s_frame_id,
    input wire s_sof, input wire s_eol, input wire s_eof,
    output wire m_valid, input wire m_ready,
    output wire [71:0] m_window,
    output wire [10:0] m_x, output wire [9:0] m_y,
    output wire [31:0] m_frame_id,
    output wire m_sof, output wire m_eol, output wire m_eof
);
    sr_luma_window3x3 window3x3 (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_luma(s_luma), .s_x(s_x), .s_y(s_y), .s_frame_id(s_frame_id),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_window(m_window),
        .m_x(m_x), .m_y(m_y), .m_frame_id(m_frame_id),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );
endmodule

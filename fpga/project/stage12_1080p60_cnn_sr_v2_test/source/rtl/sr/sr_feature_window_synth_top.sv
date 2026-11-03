`timescale 1ns/1ps
module sr_feature_window_synth_top (
    input wire clk, input wire rstn,
    input wire s_valid, output wire s_ready,
    input wire [63:0] s_features,
    input wire [31:0] s_frame_id,
    output wire m_valid, input wire m_ready,
    output wire [575:0] m_window,
    output wire [10:0] m_x, output wire [9:0] m_y,
    output wire [20:0] m_pixel_id, output wire [31:0] m_frame_id,
    output wire m_sof, output wire m_eol, output wire m_eof
);
    sr_feature_window_pipeline window_pipeline (
        .clk(clk), .rstn(rstn), .s_valid(s_valid), .s_ready(s_ready),
        .s_features(s_features), .s_frame_id(s_frame_id),
        .m_valid(m_valid), .m_ready(m_ready), .m_window(m_window),
        .m_x(m_x), .m_y(m_y), .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );
endmodule

`timescale 1ns/1ps
module sr_input_stem_timing_top (
    input wire clk,
    input wire rstn,
    input wire source_frame_start,
    input wire [1:0] source_frame_slot,
    input wire [31:0] source_frame_id,
    output wire source_done,
    output wire fatal_fault,
    output wire [15:0] read_error_count,
    output wire read_valid,
    output wire [27:0] read_addr,
    output wire [3:0] read_len,
    output wire read_reserve,
    input wire read_ready,
    input wire read_rvalid,
    input wire [255:0] read_rdata,
    input wire read_rlast,
    output wire m_valid,
    input wire m_ready,
    output wire [63:0] m_features,
    output wire [10:0] m_x,
    output wire [9:0] m_y,
    output wire [20:0] m_pixel_id,
    output wire [31:0] m_frame_id,
    output wire m_sof,
    output wire m_eol,
    output wire m_eof
);
    wire window_valid, window_ready;
    wire [71:0] window_data;
    wire [10:0] window_x;
    wire [9:0] window_y;
    wire [31:0] window_frame_id;
    wire window_sof, window_eol, window_eof;
    wire [20:0] window_pixel_id;

    sr_input_pipeline input_chain (
        .clk(clk), .rstn(rstn),
        .source_frame_start(source_frame_start),
        .source_frame_slot(source_frame_slot), .source_frame_id(source_frame_id),
        .source_done(source_done), .fatal_fault(fatal_fault),
        .read_error_count(read_error_count),
        .read_valid(read_valid), .read_addr(read_addr), .read_len(read_len),
        .read_reserve(read_reserve), .read_ready(read_ready),
        .read_rvalid(read_rvalid), .read_rdata(read_rdata), .read_rlast(read_rlast),
        .m_valid(window_valid), .m_ready(window_ready), .m_window(window_data),
        .m_x(window_x), .m_y(window_y), .m_frame_id(window_frame_id),
        .m_pixel_id(window_pixel_id),
        .m_sof(window_sof), .m_eol(window_eol), .m_eof(window_eof)
    );

    sr_stem_conv stem (
        .clk(clk), .rstn(rstn),
        .s_valid(window_valid), .s_ready(window_ready), .s_window(window_data),
        .s_x(window_x), .s_y(window_y), .s_pixel_id(window_pixel_id),
        .s_frame_id(window_frame_id), .s_sof(window_sof),
        .s_eol(window_eol), .s_eof(window_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_features(m_features),
        .m_x(m_x), .m_y(m_y), .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

endmodule

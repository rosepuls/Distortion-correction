`timescale 1ns/1ps
module sr_dma_synth_top (
    input wire clk, input wire rstn,
    input wire source_frame_start, input wire [1:0] source_frame_slot,
    input wire [31:0] source_frame_id,
    output wire m_valid, input wire m_ready, output wire [31:0] m_rgbx,
    output wire [20:0] m_pixel_id, output wire [31:0] m_frame_id,
    output wire [10:0] m_x, output wire [9:0] m_y,
    output wire m_sof, output wire m_eol, output wire m_eof,
    output wire read_valid, output wire [27:0] read_addr,
    output wire [3:0] read_len, output wire read_reserve,
    input wire read_ready, input wire read_rvalid,
    input wire [255:0] read_rdata, input wire read_rlast,
    output wire source_done, output wire fatal_fault,
    output wire [15:0] read_error_count
);
    sr_source_dma dma (
        .clk(clk), .rstn(rstn), .source_frame_start(source_frame_start),
        .source_frame_slot(source_frame_slot), .source_frame_id(source_frame_id),
        .m_valid(m_valid), .m_ready(m_ready), .m_rgbx(m_rgbx),
        .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id), .m_x(m_x), .m_y(m_y),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof),
        .read_valid(read_valid), .read_addr(read_addr), .read_len(read_len),
        .read_reserve(read_reserve), .read_ready(read_ready),
        .read_rvalid(read_rvalid), .read_rdata(read_rdata), .read_rlast(read_rlast),
        .source_done(source_done), .fatal_fault(fatal_fault),
        .read_error_count(read_error_count)
    );
endmodule

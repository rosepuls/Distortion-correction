`timescale 1ns / 1ps

// Timing-isolated streaming source chain for CNN input: DDR source DMA,
// RGBX-to-luma front end, a four-entry registered-occupancy skid FIFO, then
// the synchronous 3x3 line window. The FIFO breaks window-ready propagation
// before it can reach the front-end arithmetic and DMA controls.
module sr_input_pipeline #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer FIFO_DEPTH = 4,
    parameter integer FIFO_PTR_WIDTH = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH),
    parameter integer FIFO_COUNT_WIDTH = $clog2(FIFO_DEPTH+1)
) (
    input  wire         clk,
    input  wire         rstn,
    input  wire         source_frame_start,
    input  wire [1:0]   source_frame_slot,
    input  wire [31:0]  source_frame_id,
    output wire         source_done,
    output wire         fatal_fault,
    output wire [15:0]  read_error_count,
    output wire         read_valid,
    output wire [27:0]  read_addr,
    output wire [3:0]   read_len,
    output wire         read_reserve,
    input  wire         read_ready,
    input  wire         read_rvalid,
    input  wire [255:0] read_rdata,
    input  wire         read_rlast,
    output wire         m_valid,
    input  wire         m_ready,
    output wire [71:0]  m_window,
    output wire [10:0]  m_x,
    output wire [9:0]   m_y,
    output wire [20:0]  m_pixel_id,
    output wire [31:0]  m_frame_id,
    output wire         m_sof,
    output wire         m_eol,
    output wire         m_eof
);
    localparam integer FIFO_WIDTH = 64;
    wire dma_valid, dma_ready;
    wire [31:0] dma_rgbx, dma_frame_id;
    wire [20:0] dma_pixel_id;
    wire [10:0] dma_x;
    wire [9:0] dma_y;
    wire dma_sof, dma_eol, dma_eof;

    sr_source_dma #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) source_dma (
        .clk(clk), .rstn(rstn),
        .source_frame_start(source_frame_start),
        .source_frame_slot(source_frame_slot), .source_frame_id(source_frame_id),
        .m_valid(dma_valid), .m_ready(dma_ready), .m_rgbx(dma_rgbx),
        .m_pixel_id(dma_pixel_id), .m_frame_id(dma_frame_id),
        .m_x(dma_x), .m_y(dma_y),
        .m_sof(dma_sof), .m_eol(dma_eol), .m_eof(dma_eof),
        .read_valid(read_valid), .read_addr(read_addr), .read_len(read_len),
        .read_reserve(read_reserve), .read_ready(read_ready),
        .read_rvalid(read_rvalid), .read_rdata(read_rdata), .read_rlast(read_rlast),
        .source_done(source_done), .fatal_fault(fatal_fault),
        .read_error_count(read_error_count)
    );

    wire front_valid, front_ready;
    wire [7:0] front_luma;
    wire [20:0] front_pixel_id;
    wire [31:0] front_frame_id;
    wire [10:0] front_x;
    wire [9:0] front_y;
    wire front_sof, front_eol, front_eof;
    wire fifo_in_ready;

    sr_luma_frontend frontend (
        .clk(clk), .rstn(rstn),
        .s_valid(dma_valid), .s_ready(dma_ready), .s_rgbx(dma_rgbx),
        .s_pixel_id(dma_pixel_id), .s_frame_id(dma_frame_id),
        .s_x(dma_x), .s_y(dma_y), .s_sof(dma_sof), .s_eol(dma_eol), .s_eof(dma_eof),
        .m_valid(front_valid), .m_ready(fifo_in_ready), .m_y(front_luma),
        .m_pixel_id(front_pixel_id), .m_frame_id(front_frame_id),
        .m_x(front_x), .m_y_coord(front_y),
        .m_sof(front_sof), .m_eol(front_eol), .m_eof(front_eof)
    );

    reg [FIFO_WIDTH-1:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [FIFO_PTR_WIDTH-1:0] fifo_wr_ptr, fifo_rd_ptr;
    reg [FIFO_COUNT_WIDTH-1:0] fifo_count;
    wire fifo_out_valid = (fifo_count != 0);
    wire fifo_out_ready;
    wire fifo_push = front_valid && fifo_in_ready;
    wire fifo_pop = fifo_out_valid && fifo_out_ready;
    wire [FIFO_WIDTH-1:0] fifo_out = fifo_mem[fifo_rd_ptr];
    wire [7:0] window_luma = fifo_out[7:0];
    wire [10:0] window_x = fifo_out[18:8];
    wire [9:0] window_y = fifo_out[28:19];
    wire [31:0] window_frame_id = fifo_out[60:29];
    wire window_sof = fifo_out[61];
    wire window_eol = fifo_out[62];
    wire window_eof = fifo_out[63];

    assign fifo_in_ready = (fifo_count < FIFO_DEPTH);
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            fifo_wr_ptr <= 0;
            fifo_rd_ptr <= 0;
            fifo_count <= 0;
        end else begin
            if (fifo_push) begin
                fifo_mem[fifo_wr_ptr] <= {
                    front_eof, front_eol, front_sof, front_frame_id,
                    front_y, front_x, front_luma
                };
                if (fifo_wr_ptr == FIFO_DEPTH-1) fifo_wr_ptr <= 0;
                else fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
            end
            if (fifo_pop) begin
                if (fifo_rd_ptr == FIFO_DEPTH-1) fifo_rd_ptr <= 0;
                else fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
            end
            case ({fifo_push, fifo_pop})
                2'b10: fifo_count <= fifo_count + 1'b1;
                2'b01: fifo_count <= fifo_count - 1'b1;
                default: fifo_count <= fifo_count;
            endcase
        end
    end

    sr_luma_window3x3 #(
        .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) window3x3 (
        .clk(clk), .rstn(rstn),
        .s_valid(fifo_out_valid), .s_ready(fifo_out_ready),
        .s_luma(window_luma), .s_x(window_x), .s_y(window_y),
        .s_frame_id(window_frame_id), .s_sof(window_sof),
        .s_eol(window_eol), .s_eof(window_eof),
        .m_valid(m_valid), .m_ready(m_ready), .m_window(m_window),
        .m_x(m_x), .m_y(m_y), .m_pixel_id(m_pixel_id), .m_frame_id(m_frame_id),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );
endmodule

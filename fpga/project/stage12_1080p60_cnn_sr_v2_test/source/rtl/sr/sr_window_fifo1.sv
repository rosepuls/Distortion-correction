`timescale 1ns / 1ps

// Single-entry registered-ready buffer for wide 3x3 windows and metadata.
// s_ready depends only on the stored valid bit, not on downstream ready.
module sr_window_fifo1 #(
    parameter integer X_WIDTH = 11,
    parameter integer Y_WIDTH = 10,
    parameter integer PIXEL_ID_WIDTH = 21,
    parameter integer FRAME_ID_WIDTH = 32
) (
    input  wire                      clk,
    input  wire                      rstn,
    input  wire                      s_valid,
    output wire                      s_ready,
    input  wire [575:0]              s_window,
    input  wire [X_WIDTH-1:0]        s_x,
    input  wire [Y_WIDTH-1:0]        s_y,
    input  wire [PIXEL_ID_WIDTH-1:0] s_pixel_id,
    input  wire [FRAME_ID_WIDTH-1:0] s_frame_id,
    input  wire                      s_sof,
    input  wire                      s_eol,
    input  wire                      s_eof,
    output wire                      m_valid,
    input  wire                      m_ready,
    output wire [575:0]              m_window,
    output wire [X_WIDTH-1:0]        m_x,
    output wire [Y_WIDTH-1:0]        m_y,
    output wire [PIXEL_ID_WIDTH-1:0] m_pixel_id,
    output wire [FRAME_ID_WIDTH-1:0] m_frame_id,
    output wire                      m_sof,
    output wire                      m_eol,
    output wire                      m_eof
);
    reg stored_valid;
    reg [575:0] stored_window;
    reg [X_WIDTH-1:0] stored_x;
    reg [Y_WIDTH-1:0] stored_y;
    reg [PIXEL_ID_WIDTH-1:0] stored_pixel_id;
    reg [FRAME_ID_WIDTH-1:0] stored_frame_id;
    reg stored_sof, stored_eol, stored_eof;

    wire push = s_valid && s_ready;
    wire pop = m_valid && m_ready;
    assign s_ready = rstn && !stored_valid;
    assign m_valid = rstn && stored_valid;
    assign m_window = stored_window;
    assign m_x = stored_x;
    assign m_y = stored_y;
    assign m_pixel_id = stored_pixel_id;
    assign m_frame_id = stored_frame_id;
    assign m_sof = stored_sof;
    assign m_eol = stored_eol;
    assign m_eof = stored_eof;

    always @(posedge clk) begin
        if (!rstn) stored_valid <= 1'b0;
        else begin
            if (push) begin
                stored_window <= s_window;
                stored_x <= s_x;
                stored_y <= s_y;
                stored_pixel_id <= s_pixel_id;
                stored_frame_id <= s_frame_id;
                stored_sof <= s_sof;
                stored_eol <= s_eol;
                stored_eof <= s_eof;
                stored_valid <= 1'b1;
            end else if (pop) stored_valid <= 1'b0;
        end
    end
endmodule

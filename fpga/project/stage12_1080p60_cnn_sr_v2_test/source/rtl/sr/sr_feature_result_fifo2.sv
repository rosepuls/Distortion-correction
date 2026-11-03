`timescale 1ns / 1ps

// Two-entry registered-ready boundary between depthwise and pointwise.
// Occupancy, not downstream ready, controls s_ready. At one queued item the
// FIFO can push and pop together, sustaining one feature vector per cycle.
module sr_feature_result_fifo2 #(
    parameter integer X_WIDTH = 11,
    parameter integer Y_WIDTH = 10,
    parameter integer PIXEL_ID_WIDTH = 21,
    parameter integer FRAME_ID_WIDTH = 32
) (
    input  wire                      clk,
    input  wire                      rstn,
    input  wire                      s_valid,
    output wire                      s_ready,
    input  wire [63:0]               s_features,
    input  wire [63:0]               s_skip,
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
    output wire [63:0]               m_skip,
    output wire [X_WIDTH-1:0]        m_x,
    output wire [Y_WIDTH-1:0]        m_y,
    output wire [PIXEL_ID_WIDTH-1:0] m_pixel_id,
    output wire [FRAME_ID_WIDTH-1:0] m_frame_id,
    output wire                      m_sof,
    output wire                      m_eol,
    output wire                      m_eof
);
    reg [1:0] count;
    reg read_ptr, write_ptr;
    reg [63:0] features_mem [0:1];
    reg [63:0] skip_mem [0:1];
    reg [X_WIDTH-1:0] x_mem [0:1];
    reg [Y_WIDTH-1:0] y_mem [0:1];
    reg [PIXEL_ID_WIDTH-1:0] pixel_id_mem [0:1];
    reg [FRAME_ID_WIDTH-1:0] frame_id_mem [0:1];
    reg sof_mem [0:1], eol_mem [0:1], eof_mem [0:1];

    wire push = s_valid && s_ready;
    wire pop = m_valid && m_ready;

    assign s_ready = rstn && (count != 2);
    assign m_valid = rstn && (count != 0);
    assign m_features = features_mem[read_ptr];
    assign m_skip = skip_mem[read_ptr];
    assign m_x = x_mem[read_ptr];
    assign m_y = y_mem[read_ptr];
    assign m_pixel_id = pixel_id_mem[read_ptr];
    assign m_frame_id = frame_id_mem[read_ptr];
    assign m_sof = sof_mem[read_ptr];
    assign m_eol = eol_mem[read_ptr];
    assign m_eof = eof_mem[read_ptr];

    always @(posedge clk) begin
        if (!rstn) begin
            count <= 0;
            read_ptr <= 0;
            write_ptr <= 0;
        end else begin
            if (push) begin
                features_mem[write_ptr] <= s_features;
                skip_mem[write_ptr] <= s_skip;
                x_mem[write_ptr] <= s_x;
                y_mem[write_ptr] <= s_y;
                pixel_id_mem[write_ptr] <= s_pixel_id;
                frame_id_mem[write_ptr] <= s_frame_id;
                sof_mem[write_ptr] <= s_sof;
                eol_mem[write_ptr] <= s_eol;
                eof_mem[write_ptr] <= s_eof;
                write_ptr <= ~write_ptr;
            end
            if (pop) read_ptr <= ~read_ptr;
            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule

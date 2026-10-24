`timescale 1ns / 1ps

module coordinate_fifo #(
    parameter integer DEPTH = 16,
    parameter integer LEVEL_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1)
) (
    input  wire                       clk,
    input  wire                       rstn,

    input  wire                       s_valid,
    output wire                       s_ready,
    input  wire signed [31:0]         s_sx,
    input  wire signed [31:0]         s_sy,
    input  wire                       s_geometry_valid,
    input  wire signed [31:0]         s_j00,
    input  wire signed [31:0]         s_j01,
    input  wire signed [31:0]         s_j10,
    input  wire signed [31:0]         s_j11,
    input  wire                       s_j_valid,
    input  wire [19:0]                s_pixel_id,
    input  wire [31:0]                s_frame_id,
    input  wire [15:0]                s_param_version,
    input  wire                       s_sof,
    input  wire                       s_eol,
    input  wire                       s_eof,

    output wire                       m_valid,
    input  wire                       m_ready,
    output wire signed [31:0]         m_sx,
    output wire signed [31:0]         m_sy,
    output wire                       m_geometry_valid,
    output wire signed [31:0]         m_j00,
    output wire signed [31:0]         m_j01,
    output wire signed [31:0]         m_j10,
    output wire signed [31:0]         m_j11,
    output wire                       m_j_valid,
    output wire [19:0]                m_pixel_id,
    output wire [31:0]                m_frame_id,
    output wire [15:0]                m_param_version,
    output wire                       m_sof,
    output wire                       m_eol,
    output wire                       m_eof,
    output wire [LEVEL_WIDTH-1:0]     level
);

    localparam integer POINTER_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam integer PAYLOAD_WIDTH = 265;

    reg [PAYLOAD_WIDTH-1:0] storage [0:DEPTH-1];
    reg [POINTER_WIDTH-1:0] write_pointer;
    reg [POINTER_WIDTH-1:0] read_pointer;
    reg [LEVEL_WIDTH-1:0] count;

    wire push;
    wire pop;
    wire [PAYLOAD_WIDTH-1:0] head_payload;

    assign m_valid = rstn && (count != 0);
    assign s_ready = rstn && ((count < DEPTH) || (m_valid && m_ready));
    assign push = s_valid && s_ready;
    assign pop = m_valid && m_ready;
    assign level = count;

    assign head_payload = storage[read_pointer];
    assign {
        m_sx,
        m_sy,
        m_geometry_valid,
        m_j00,
        m_j01,
        m_j10,
        m_j11,
        m_j_valid,
        m_pixel_id,
        m_frame_id,
        m_param_version,
        m_sof,
        m_eol,
        m_eof
    } = head_payload;

    always @(posedge clk) begin
        if (!rstn) begin
            write_pointer <= {POINTER_WIDTH{1'b0}};
            read_pointer  <= {POINTER_WIDTH{1'b0}};
            count         <= {LEVEL_WIDTH{1'b0}};
        end else begin
            if (push) begin
                storage[write_pointer] <= {
                    s_sx,
                    s_sy,
                    s_geometry_valid,
                    s_j00,
                    s_j01,
                    s_j10,
                    s_j11,
                    s_j_valid,
                    s_pixel_id,
                    s_frame_id,
                    s_param_version,
                    s_sof,
                    s_eol,
                    s_eof
                };
                if (write_pointer == DEPTH - 1)
                    write_pointer <= {POINTER_WIDTH{1'b0}};
                else
                    write_pointer <= write_pointer + 1'b1;
            end

            if (pop) begin
                if (read_pointer == DEPTH - 1)
                    read_pointer <= {POINTER_WIDTH{1'b0}};
                else
                    read_pointer <= read_pointer + 1'b1;
            end

            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule

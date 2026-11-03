`timescale 1ns / 1ps

// Four-entry feature/frame FIFO. Input ready is derived only from registered
// occupancy so downstream ready does not form a combinational path to stem.
module sr_feature_fifo4 #(
    parameter integer FRAME_ID_WIDTH = 32,
    parameter integer PTR_WIDTH = 2
) (
    input  wire                         clk,
    input  wire                         rstn,
    input  wire                         s_valid,
    output wire                         s_ready,
    input  wire [63:0]                  s_features,
    input  wire [FRAME_ID_WIDTH-1:0]    s_frame_id,
    output wire                         m_valid,
    input  wire                         m_ready,
    output wire [63:0]                  m_features,
    output wire [FRAME_ID_WIDTH-1:0]    m_frame_id
);
    reg [63:0] feature_mem [0:3];
    reg [FRAME_ID_WIDTH-1:0] frame_mem [0:3];
    reg [PTR_WIDTH-1:0] write_ptr, read_ptr;
    reg [PTR_WIDTH:0] count;
    wire push = s_valid && s_ready;
    wire pop = m_valid && m_ready;

    assign s_ready = rstn && (count < 4);
    assign m_valid = rstn && (count != 0);
    assign m_features = feature_mem[read_ptr];
    assign m_frame_id = frame_mem[read_ptr];

    always @(posedge clk) begin
        if (!rstn) begin
            write_ptr <= {PTR_WIDTH{1'b0}};
            read_ptr <= {PTR_WIDTH{1'b0}};
            count <= {(PTR_WIDTH+1){1'b0}};
        end else begin
            if (push) begin
                feature_mem[write_ptr] <= s_features;
                frame_mem[write_ptr] <= s_frame_id;
                write_ptr <= write_ptr + 1'b1;
            end
            if (pop) read_ptr <= read_ptr + 1'b1;
            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule

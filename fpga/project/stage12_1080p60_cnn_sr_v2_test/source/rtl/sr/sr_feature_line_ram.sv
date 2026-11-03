`timescale 1ns / 1ps

// One synchronous read/write feature row; sized for eight uint8 channels.
module sr_feature_line_ram #(
    parameter integer DATA_WIDTH = 64,
    parameter integer DEPTH = 1282,
    parameter integer ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  wire                     clk,
    input  wire                     wr_en,
    input  wire [ADDR_WIDTH-1:0]    wr_addr,
    input  wire [DATA_WIDTH-1:0]    wr_data,
    input  wire                     rd_en,
    input  wire [ADDR_WIDTH-1:0]    rd_addr,
    output reg  [DATA_WIDTH-1:0]    rd_data
);
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    always @(posedge clk) begin
        if (wr_en) mem[wr_addr] <= wr_data;
        if (rd_en) rd_data <= mem[rd_addr];
    end
endmodule

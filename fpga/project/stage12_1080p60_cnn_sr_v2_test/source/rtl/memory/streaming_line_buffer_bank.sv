`timescale 1ns / 1ps

// One 32-bit lane of a source row. The 8 banks accept one full 256-bit DDR
// beat per cycle and expose synchronous pixel reads for neighboring x values.
module streaming_line_buffer_bank #(
    parameter integer DEPTH = 160,
    parameter integer ADDR_WIDTH = 8
) (
    input  wire                  clk,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [31:0]           wr_data,
    input  wire                  rd_en,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output reg  [31:0]           rd_data
);
    (* ram_style = "block" *) reg [31:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
        if (rd_en)
            rd_data <= mem[rd_addr];
    end
endmodule

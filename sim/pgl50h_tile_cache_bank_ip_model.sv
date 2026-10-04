`timescale 1ns/1ps

// XSim model for pgl50h_tile_cache_bank_ip.  The PDS build uses the vendor
// wrapper with the same module/port contract instead of this file.
module pgl50h_tile_cache_bank_ip #(
    parameter integer ADDR_WIDTH = 11
) (
    input  wire [127:0] wr_data,
    input  wire [ADDR_WIDTH-1:0]  wr_addr,
    input  wire         wr_en,
    input  wire         wr_clk,
    input  wire         wr_clk_en,
    input  wire         wr_rst,
    input  wire [3:0]   wr_byte_en,
    input  wire         wr_addr_strobe,
    output reg  [127:0] rd_data,
    input  wire [ADDR_WIDTH-1:0]  rd_addr,
    input  wire         rd_clk,
    input  wire         rd_clk_en,
    input  wire         rd_rst,
    input  wire         rd_oce,
    input  wire         rd_addr_strobe
);
    localparam integer BANK_DEPTH = (1 << ADDR_WIDTH);
    reg [127:0] mem [0:BANK_DEPTH-1];
    integer i;

    initial begin
        for (i = 0; i < BANK_DEPTH; i = i + 1)
            mem[i] = 128'd0;
    end

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            rd_data <= 128'd0;
        end else begin
            if (wr_clk_en && wr_en)
                mem[wr_addr] <= wr_data;
            if (rd_clk_en && rd_oce)
                rd_data <= mem[rd_addr];
        end
    end
endmodule

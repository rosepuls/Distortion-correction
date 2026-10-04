`timescale 1ns/1ps

// Synchronous 128-bit Tile Cache bank.
//
// The public interface is technology-neutral.  PDS resolves
// pgl50h_tile_cache_bank_ip to the PGL50H DRM wrapper, while XSim supplies a
// behavioral module with the same name from sim/pgl50h_tile_cache_bank_ip_model.sv.
module tile_cache_bank_ram #(
    parameter integer BANK_READ_LATENCY = 1,
    parameter integer BANK_ADDR_WIDTH = 11
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         wr_en,
    input  wire [BANK_ADDR_WIDTH-1:0] wr_addr,
    input  wire [127:0] wr_data,
    input  wire         rd_en,
    input  wire [BANK_ADDR_WIDTH-1:0] rd_addr,
    output wire [127:0] rd_data,
    output wire         rd_valid
);
    initial begin
        if (BANK_READ_LATENCY < 1)
            $error("BANK_READ_LATENCY must be at least one clock");
    end

    wire [127:0] ip_rd_data;
    reg [BANK_READ_LATENCY-1:0] rd_valid_pipe;
    integer latency_index;

    pgl50h_tile_cache_bank_ip #(
        .ADDR_WIDTH(BANK_ADDR_WIDTH)
    ) bank_ip (
        .wr_data(wr_data),
        .wr_addr(wr_addr),
        .wr_en(wr_en),
        .wr_clk(clk),
        .wr_clk_en(1'b1),
        .wr_rst(!rst_n),
        .wr_byte_en(4'b1111),
        .wr_addr_strobe(1'b0),
        .rd_data(ip_rd_data),
        .rd_addr(rd_addr),
        .rd_clk(clk),
        .rd_clk_en(rd_en),
        .rd_rst(!rst_n),
        .rd_oce(rd_en),
        .rd_addr_strobe(1'b0)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_valid_pipe <= {BANK_READ_LATENCY{1'b0}};
        end else begin
            rd_valid_pipe[0] <= rd_en;
            for (latency_index = 1;
                 latency_index < BANK_READ_LATENCY;
                 latency_index = latency_index + 1)
                rd_valid_pipe[latency_index] <= rd_valid_pipe[latency_index-1];
        end
    end

    assign rd_data = ip_rd_data;
    assign rd_valid = rd_valid_pipe[BANK_READ_LATENCY-1];
endmodule

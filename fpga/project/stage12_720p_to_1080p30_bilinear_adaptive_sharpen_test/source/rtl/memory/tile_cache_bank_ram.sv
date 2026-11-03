`timescale 1ns / 1ps

// Device-neutral replacement for the old PGL50H-only bank wrapper. Memory
// contents are not reset; the cache invalidates its tags at a frame boundary.
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
    reg [127:0] memory [0:(1 << BANK_ADDR_WIDTH)-1];
    reg [127:0] data_pipe [0:BANK_READ_LATENCY-1];
    reg [BANK_READ_LATENCY-1:0] valid_pipe;
    integer data_stage;
    integer valid_stage;

    always @(posedge clk) begin
        if (wr_en)
            memory[wr_addr] <= wr_data;
        if (rd_en)
            data_pipe[0] <= memory[rd_addr];
        for (data_stage = 1; data_stage < BANK_READ_LATENCY;
             data_stage = data_stage + 1)
            data_pipe[data_stage] <= data_pipe[data_stage-1];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_pipe <= {BANK_READ_LATENCY{1'b0}};
        else begin
            valid_pipe[0] <= rd_en;
            for (valid_stage = 1; valid_stage < BANK_READ_LATENCY;
                 valid_stage = valid_stage + 1)
                valid_pipe[valid_stage] <= valid_pipe[valid_stage-1];
        end
    end

    assign rd_data = data_pipe[BANK_READ_LATENCY-1];
    assign rd_valid = valid_pipe[BANK_READ_LATENCY-1];
endmodule

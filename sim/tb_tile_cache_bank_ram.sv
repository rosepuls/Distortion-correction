`timescale 1ns/1ps

module tb_tile_cache_bank_ram;
    localparam integer READ_LATENCY = 1;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg wr_en = 1'b0;
    reg [10:0] wr_addr = 11'd0;
    reg [127:0] wr_data = 128'd0;
    reg rd_en = 1'b0;
    reg [10:0] rd_addr = 11'd0;
    wire [127:0] rd_data;
    wire rd_valid;

    integer errors = 0;
    integer cycle;
    reg [10:0] expected_addr [0:31];

    always #5 clk = ~clk;

    tile_cache_bank_ram #(
        .BANK_READ_LATENCY(READ_LATENCY)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_en(rd_en), .rd_addr(rd_addr),
        .rd_data(rd_data), .rd_valid(rd_valid)
    );

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;

        @(negedge clk);
        wr_en <= 1'b1;
        wr_addr <= 11'd77;
        wr_data <= 128'h0123_4567_89ab_cdef_1020_3040_5060_7080;
        rd_en <= 1'b0;
        @(posedge clk);
        @(negedge clk);
        wr_en <= 1'b0;

        // Consecutive reads must retire at one item per clock.
        rd_en <= 1'b1;
        for (cycle = 0; cycle < 32; cycle = cycle + 1) begin
            rd_addr <= (cycle == 0) ? 11'd77 : (cycle + 11'd100);
            expected_addr[cycle] <= (cycle == 0) ? 11'd77 : (cycle + 11'd100);
            @(posedge clk);
            if (cycle >= READ_LATENCY) begin
                if (!rd_valid)
                    $fatal(1, "TEST_FAIL: missing rd_valid at cycle %0d", cycle);
                if (rd_data !== ((expected_addr[cycle-READ_LATENCY] == 11'd77)
                                 ? 128'h0123_4567_89ab_cdef_1020_3040_5060_7080
                                 : 128'd0)) begin
                    $fatal(1, "TEST_FAIL: read data/address mismatch at cycle %0d", cycle);
                end
            end
        end
        rd_en <= 1'b0;
        @(posedge clk);
        @(negedge clk);
        if (rd_valid)
            $fatal(1, "TEST_FAIL: rd_valid did not drain");

        if (errors != 0)
            $fatal(1, "TEST_FAIL: tile_cache_bank_ram errors=%0d", errors);
        $display("TEST_PASS: tile_cache_bank_ram");
        $finish;
    end
endmodule

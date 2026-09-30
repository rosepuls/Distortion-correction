`timescale 1ns/1ps

// 独立验证同步 1 读 1 写行缓存 RAM：读写同一地址时读出旧数据。
module tb_line_ram_1r1w;
    reg clk = 1'b0;
    reg rd_en = 1'b0;
    reg [2:0] rd_addr = 3'd0;
    wire [7:0] rd_data;
    reg wr_en = 1'b0;
    reg [2:0] wr_addr = 3'd0;
    reg [7:0] wr_data = 8'd0;
    integer errors = 0;

    always #5 clk = ~clk;

    line_ram_1r1w #(
        .ADDR_WIDTH(3),
        .DATA_WIDTH(8)
    ) dut (
        .clk(clk),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data)
    );

    task expect_read;
        input [7:0] expected;
        begin
            @(negedge clk);
            if (rd_data !== expected) begin
                $display("TEST_FAIL: line_ram expected=%0d got=%0d", expected, rd_data);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // 先写 42 到地址 3；下一拍对地址 3 发起同步读。
        @(negedge clk);
        wr_en = 1'b1; wr_addr = 3'd3; wr_data = 8'd42;
        @(negedge clk);
        wr_en = 1'b0; rd_en = 1'b1; rd_addr = 3'd3;
        expect_read(8'd42);

        // 同拍读写地址 3：必须读出写入前的 42，之后再读到新值 99。
        @(negedge clk);
        wr_en = 1'b1; wr_addr = 3'd3; wr_data = 8'd99;
        expect_read(8'd42);
        @(negedge clk);
        wr_en = 1'b0; rd_en = 1'b1; rd_addr = 3'd3;
        expect_read(8'd99);

        if (errors == 0) $display("TEST_PASS: line_ram_1r1w");
        else $fatal(1, "TEST_FAIL: line_ram_1r1w errors=%0d", errors);
        $finish;
    end
endmodule

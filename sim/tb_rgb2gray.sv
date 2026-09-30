`timescale 1ns/1ps

module tb_rgb2gray;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [23:0] in_pixel = 24'd0;
    reg in_valid = 1'b0;
    reg in_sof = 1'b0;
    reg in_eol = 1'b0;
    wire [7:0] out_pixel;
    wire out_valid, out_sof, out_eol;
    integer errors = 0;

    always #5 clk = ~clk;

    rgb2gray dut (
        .clk(clk), .rst_n(rst_n), .in_pixel(in_pixel), .in_valid(in_valid),
        .in_sof(in_sof), .in_eol(in_eol), .out_pixel(out_pixel),
        .out_valid(out_valid), .out_sof(out_sof), .out_eol(out_eol)
    );

    task apply_and_check;
        input [23:0] pixel;
        input [7:0] expected;
        input sof;
        input eol;
        begin
            @(negedge clk);
            in_pixel = pixel; in_valid = 1'b1; in_sof = sof; in_eol = eol;
            @(negedge clk);
            if (!out_valid || out_pixel !== expected || out_sof !== sof || out_eol !== eol) begin
                $display("TEST_FAIL: rgb2gray input=%h got=%0d expected=%0d", pixel, out_pixel, expected);
                errors = errors + 1;
            end
            in_valid = 1'b0; in_sof = 1'b0; in_eol = 1'b0;
        end
    endtask

    // 显式插入一个空拍，确认 valid 与帧/行标志同步清零。
    task check_bubble;
        begin
            @(negedge clk);
            in_valid = 1'b0; in_sof = 1'b0; in_eol = 1'b0;
            @(negedge clk);
            if (out_valid !== 1'b0 || out_sof !== 1'b0 || out_eol !== 1'b0) begin
                $display("TEST_FAIL: rgb2gray bubble control valid/sof/eol=%b/%b/%b", out_valid, out_sof, out_eol);
                errors = errors + 1;
            end
        end
    endtask

    // 在输出可能有效时异步复位，检查控制信号立即清零。
    task assert_reset_and_check;
        begin
            rst_n = 1'b0;
            #1;
            if (out_valid !== 1'b0 || out_sof !== 1'b0 || out_eol !== 1'b0 || out_pixel !== 8'd0) begin
                $display("TEST_FAIL: rgb2gray reset did not clear outputs");
                errors = errors + 1;
            end
            in_valid = 1'b0; in_sof = 1'b0; in_eol = 1'b0;
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        apply_and_check(24'h000000, 8'd0,   1'b1, 1'b0);
        apply_and_check(24'hffffff, 8'd255, 1'b0, 1'b0);
        apply_and_check(24'hff0000, 8'd76,  1'b0, 1'b0);
        apply_and_check(24'h00ff00, 8'd149, 1'b0, 1'b0);
        apply_and_check(24'h0000ff, 8'd28,  1'b0, 1'b1);
        check_bubble();

        // 第二帧使用不同数据，验证 SOF/EOL 随对应像素对齐。
        apply_and_check(24'h010203, 8'd1, 1'b1, 1'b1);
        assert_reset_and_check();
        apply_and_check(24'hffffff, 8'd255, 1'b1, 1'b1);
        check_bubble();
        if (errors == 0) $display("TEST_PASS: rgb2gray");
        else $fatal(1, "TEST_FAIL: rgb2gray errors=%0d", errors);
        $finish;
    end
endmodule

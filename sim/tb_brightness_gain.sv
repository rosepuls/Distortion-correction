`timescale 1ns/1ps

module tb_brightness_gain;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [7:0] in_pixel = 8'd0;
    reg in_valid = 1'b0, in_sof = 1'b0, in_eol = 1'b0;
    reg [15:0] cfg_gain = 16'h1000;
    reg signed [9:0] cfg_offset = 10'sd0;
    wire [7:0] out_pixel;
    wire out_valid, out_sof, out_eol;
    integer errors = 0;

    always #5 clk = ~clk;

    brightness_gain dut (
        .clk(clk), .rst_n(rst_n), .in_pixel(in_pixel), .in_valid(in_valid),
        .in_sof(in_sof), .in_eol(in_eol), .cfg_gain(cfg_gain),
        .cfg_offset(cfg_offset), .out_pixel(out_pixel), .out_valid(out_valid),
        .out_sof(out_sof), .out_eol(out_eol)
    );

    task apply_and_check;
        input [7:0] pixel;
        input [15:0] gain;
        input signed [9:0] offset;
        input sof, eol;
        input [7:0] expected;
        begin
            @(negedge clk);
            in_pixel = pixel; cfg_gain = gain; cfg_offset = offset;
            in_valid = 1'b1; in_sof = sof; in_eol = eol;
            @(negedge clk);
            if (!out_valid || out_pixel !== expected || out_sof !== sof || out_eol !== eol) begin
                $display("TEST_FAIL: brightness_gain pixel=%0d got=%0d expected=%0d", pixel, out_pixel, expected);
                errors = errors + 1;
            end
            in_valid = 1'b0; in_sof = 1'b0; in_eol = 1'b0;
        end
    endtask

    task check_bubble;
        begin
            @(negedge clk);
            in_valid=0; in_sof=0; in_eol=0;
            @(negedge clk);
            if (out_valid!==0 || out_sof!==0 || out_eol!==0) begin
                $display("TEST_FAIL: brightness_gain bubble control valid/sof/eol=%b/%b/%b",out_valid,out_sof,out_eol);
                errors=errors+1;
            end
        end
    endtask

    task assert_reset_and_check;
        begin
            rst_n=0;
            #1;
            if (out_valid!==0 || out_sof!==0 || out_eol!==0 || out_pixel!==0) begin
                $display("TEST_FAIL: brightness_gain reset did not clear outputs");
                errors=errors+1;
            end
            in_valid=0; in_sof=0; in_eol=0;
            @(negedge clk);
            rst_n=1;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        apply_and_check(8'd128, 16'h1000, 10'sd0,    1'b1, 1'b0, 8'd128);
        // 帧中途更改配置不能改变已锁存的帧参数。
        apply_and_check(8'd128, 16'h2000, 10'sd20,   1'b0, 1'b0, 8'd128);
        apply_and_check(8'd200, 16'h2000, 10'sd10,   1'b1, 1'b0, 8'd255);
        apply_and_check(8'd20,  16'h0000, 10'sd0,    1'b0, 1'b0, 8'd50);
        apply_and_check(8'd255, 16'h1000, -10'sd200, 1'b1, 1'b0, 8'd55);
        apply_and_check(8'd0,   16'h1000, -10'sd200, 1'b0, 1'b1, 8'd0);
        check_bubble();

        // 第二帧更换增益；低端和高端饱和边界也由原向量覆盖。
        apply_and_check(8'd64, 16'h2000, 10'sd10, 1'b1, 1'b1, 8'd138);
        assert_reset_and_check();
        apply_and_check(8'd77, 16'h1000, 10'sd0, 1'b1, 1'b1, 8'd77);
        check_bubble();
        if (errors == 0) $display("TEST_PASS: brightness_gain");
        else $fatal(1, "TEST_FAIL: brightness_gain errors=%0d", errors);
        $finish;
    end
endmodule

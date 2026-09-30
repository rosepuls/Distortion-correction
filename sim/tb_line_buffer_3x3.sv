`timescale 1ns/1ps

module tb_line_buffer_3x3;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [7:0] in_pixel = 0;
    reg in_valid = 0, in_sof = 0, in_eol = 0;
    wire [7:0] tap_top, tap_middle, tap_bottom;
    wire out_valid, out_sof, out_eol, out_synthetic;
    integer errors = 0;

    always #5 clk = ~clk;

    line_buffer_3x3 #(.IMAGE_WIDTH(3), .IMAGE_HEIGHT(2), .PIXEL_WIDTH(8)) dut (
        .clk(clk), .rst_n(rst_n), .in_pixel(in_pixel), .in_valid(in_valid),
        .in_sof(in_sof), .in_eol(in_eol), .tap_top(tap_top),
        .tap_middle(tap_middle), .tap_bottom(tap_bottom), .out_valid(out_valid),
        .out_sof(out_sof), .out_eol(out_eol), .out_synthetic(out_synthetic)
    );

    task send_and_check;
        input [7:0] pixel, expected_top, expected_middle, expected_bottom;
        input sof, eol;
        begin
            @(negedge clk);
            // 两个真实像素之间至少有一个 valid=0 周期，输出不得残留上拍标志。
            if (out_valid!==0 || out_sof!==0 || out_eol!==0 || out_synthetic!==0) begin
                $display("TEST_FAIL: line_buffer bubble was not invalid"); errors=errors+1;
            end
            in_pixel = pixel; in_valid = 1'b1; in_sof = sof; in_eol = eol;
            @(negedge clk);
            // 行 RAM 采用同步读，因此当前输入不能在同一拍直接输出。
            if (out_valid !== 1'b0) begin
                $display("TEST_FAIL: line_buffer output arrived before synchronous RAM read completed");
                errors = errors + 1;
            end
            // 输入只保持一个时钟周期；下一拍只等待同步 RAM 的读结果。
            in_valid = 1'b0; in_sof = 1'b0; in_eol = 1'b0;
            @(negedge clk);
            if (!out_valid || out_synthetic || tap_top !== expected_top ||
                tap_middle !== expected_middle || tap_bottom !== expected_bottom ||
                out_sof !== sof || out_eol !== eol) begin
                $display("TEST_FAIL: line_buffer real got=%0d,%0d,%0d", tap_top, tap_middle, tap_bottom);
                errors = errors + 1;
            end
        end
    endtask

    task check_flush;
        input [7:0] expected_top, expected_middle;
        input expected_eol;
        begin
            @(negedge clk);
            if (!out_valid || !out_synthetic || tap_top !== expected_top ||
                tap_middle !== expected_middle || tap_bottom !== 8'd0 || out_eol !== expected_eol) begin
                $display("TEST_FAIL: line_buffer flush got=%0d,%0d,%0d", tap_top, tap_middle, tap_bottom);
                errors = errors + 1;
            end
        end
    endtask

    task assert_reset_and_check;
        begin
            rst_n=0; #1;
            if (out_valid!==0 || out_sof!==0 || out_eol!==0 || out_synthetic!==0 ||
                tap_top!==0 || tap_middle!==0 || tap_bottom!==0) begin
                $display("TEST_FAIL: line_buffer reset did not clear outputs"); errors=errors+1;
            end
            in_valid=0;in_sof=0;in_eol=0;
            @(negedge clk);rst_n=1;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        send_and_check(1, 0, 0, 1, 1, 0);
        send_and_check(2, 0, 0, 2, 0, 0);
        send_and_check(3, 0, 0, 3, 0, 1);
        send_and_check(4, 0, 1, 4, 0, 0);
        send_and_check(5, 0, 2, 5, 0, 0);
        send_and_check(6, 0, 3, 6, 0, 1);
        check_flush(1, 4, 0); check_flush(2, 5, 0); check_flush(3, 6, 1);
        check_flush(4, 0, 0); check_flush(5, 0, 0); check_flush(6, 0, 1);
        // 第一帧 flush 完成后立即送第二帧，验证坐标重新从 SOF=1 开始。
        send_and_check(11, 0, 0, 11, 1, 0);
        send_and_check(12, 0, 0, 12, 0, 0);
        send_and_check(13, 0, 0, 13, 0, 1);
        send_and_check(14, 0, 11, 14, 0, 0);
        send_and_check(15, 0, 12, 15, 0, 0);
        send_and_check(16, 0, 13, 16, 0, 1);
        check_flush(11, 14, 0); check_flush(12, 15, 0); check_flush(13, 16, 1);
        check_flush(14, 0, 0); check_flush(15, 0, 0); check_flush(16, 0, 1);
        assert_reset_and_check();
        // 在一帧中途再次复位；旧帧行缓存不得污染复位后的新帧首像素。
        send_and_check(21, 0, 0, 21, 1, 0);
        assert_reset_and_check();
        send_and_check(31, 0, 0, 31, 1, 1);
        if (errors == 0) $display("TEST_PASS: line_buffer_3x3");
        else $fatal(1, "TEST_FAIL: line_buffer_3x3 errors=%0d", errors);
        $finish;
    end
endmodule

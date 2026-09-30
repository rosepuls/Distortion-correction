`timescale 1ns/1ps

module tb_window_3x3;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [7:0] tap_top = 0, tap_middle = 0, tap_bottom = 0;
    reg in_valid = 0, in_sof = 0, in_eol = 0, in_synthetic = 0;
    wire [7:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    wire out_valid, out_sof, out_eol;
    integer errors = 0;
    integer output_count = 0;

    always #5 clk = ~clk;

    window_3x3 #(.IMAGE_WIDTH(3), .IMAGE_HEIGHT(2), .PIXEL_WIDTH(8)) dut (
        .clk(clk), .rst_n(rst_n), .tap_top(tap_top), .tap_middle(tap_middle),
        .tap_bottom(tap_bottom), .in_valid(in_valid), .in_sof(in_sof),
        .in_eol(in_eol), .in_synthetic(in_synthetic), .p00(p00), .p01(p01),
        .p02(p02), .p10(p10), .p11(p11), .p12(p12), .p20(p20), .p21(p21),
        .p22(p22), .out_valid(out_valid), .out_sof(out_sof), .out_eol(out_eol)
    );

    task compare_window;
        input [7:0] e00,e01,e02,e10,e11,e12,e20,e21,e22;
        input expected_sof, expected_eol;
        begin
            if (p00!==e00 || p01!==e01 || p02!==e02 || p10!==e10 || p11!==e11 ||
                p12!==e12 || p20!==e20 || p21!==e21 || p22!==e22 ||
                out_sof!==expected_sof || out_eol!==expected_eol) begin
                $display("TEST_FAIL: window_3x3 index=%0d", output_count);
                $display("  got:      %0d %0d %0d | %0d %0d %0d | %0d %0d %0d sof=%b eol=%b",
                    p00,p01,p02,p10,p11,p12,p20,p21,p22,out_sof,out_eol);
                $display("  expected: %0d %0d %0d | %0d %0d %0d | %0d %0d %0d sof=%b eol=%b",
                    e00,e01,e02,e10,e11,e12,e20,e21,e22,expected_sof,expected_eol);
                errors = errors + 1;
            end
        end
    endtask

    always @(negedge clk) begin
        if (out_valid) begin
            case (output_count)
                0: compare_window(0,0,0, 0,1,2, 0,4,5, 1,0);
                1: compare_window(0,0,0, 1,2,3, 4,5,6, 0,0);
                2: compare_window(0,0,0, 2,3,0, 5,6,0, 0,1);
                3: compare_window(0,1,2, 0,4,5, 0,0,0, 0,0);
                4: compare_window(1,2,3, 4,5,6, 0,0,0, 0,0);
                5: compare_window(2,3,0, 5,6,0, 0,0,0, 0,1);
                6: compare_window(0,0,0, 0,11,12, 0,14,15, 1,0);
                7: compare_window(0,0,0, 11,12,13, 14,15,16, 0,0);
                8: compare_window(0,0,0, 12,13,0, 15,16,0, 0,1);
                9: compare_window(0,11,12, 0,14,15, 0,0,0, 0,0);
                10: compare_window(11,12,13, 14,15,16, 0,0,0, 0,0);
                11: compare_window(12,13,0, 15,16,0, 0,0,0, 0,1);
                12: compare_window(0,0,0, 0,21,22, 0,24,25, 1,0);
                default: begin
                    $display("TEST_FAIL: window_3x3 produced extra output");
                    errors = errors + 1;
                end
            endcase
            output_count = output_count + 1;
        end
    end

    task send_tap;
        input [7:0] top_value, middle_value, bottom_value;
        input sof, eol, synthetic;
        begin
            @(negedge clk);
            // send_tap 每次调用前有一个空拍，确认空拍不会误产生窗口。
            if(out_valid!==0 || out_sof!==0 || out_eol!==0) begin
                $display("TEST_FAIL: window_3x3 bubble produced output");errors=errors+1;
            end
            tap_top=top_value; tap_middle=middle_value; tap_bottom=bottom_value;
            in_valid=1'b1; in_sof=sof; in_eol=eol; in_synthetic=synthetic;
            @(negedge clk);
            in_valid=1'b0; in_sof=1'b0; in_eol=1'b0; in_synthetic=1'b0;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        send_tap(0,0,1, 1,0,0); send_tap(0,0,2, 0,0,0); send_tap(0,0,3, 0,1,0);
        send_tap(0,1,4, 0,0,0); send_tap(0,2,5, 0,0,0); send_tap(0,3,6, 0,1,0);
        send_tap(1,4,0, 0,0,1); send_tap(2,5,0, 0,0,1); send_tap(3,6,0, 0,1,1);
        send_tap(4,0,0, 0,0,1); send_tap(5,0,0, 0,0,1); send_tap(6,0,0, 0,1,1);
        repeat (2) @(negedge clk);
        if (output_count !== 6) begin
            $display("TEST_FAIL: window_3x3 first-frame output_count=%0d expected=6", output_count);
            errors = errors + 1;
        end
        // 第二帧保持原测试结构，只更换像素值，覆盖帧状态重新同步。
        send_tap(0,0,11, 1,0,0); send_tap(0,0,12, 0,0,0); send_tap(0,0,13, 0,1,0);
        send_tap(0,11,14, 0,0,0); send_tap(0,12,15, 0,0,0); send_tap(0,13,16, 0,1,0);
        send_tap(11,14,0, 0,0,1); send_tap(12,15,0, 0,0,1); send_tap(13,16,0, 0,1,1);
        send_tap(14,0,0, 0,0,1); send_tap(15,0,0, 0,0,1); send_tap(16,0,0, 0,1,1);
        repeat (2) @(negedge clk);
        if (output_count !== 12) begin
            $display("TEST_FAIL: window_3x3 two-frame output_count=%0d expected=12", output_count);
            errors = errors + 1;
        end
        // 复位清除内部水平历史；重新输入一帧开头，确认恢复后窗口数据干净。
        send_tap(0,0,99, 1,0,0);
        rst_n=0; #1;
        if(out_valid!==0 || out_sof!==0 || out_eol!==0) begin
            $display("TEST_FAIL: window_3x3 reset did not clear control outputs");errors=errors+1;
        end
        in_valid=0;in_sof=0;in_eol=0;in_synthetic=0;
        @(negedge clk);rst_n=1;
        send_tap(0,0,21, 1,0,0); send_tap(0,0,22, 0,0,0); send_tap(0,0,23, 0,1,0);
        send_tap(0,21,24, 0,0,0); send_tap(0,22,25, 0,0,0);
        repeat (2) @(negedge clk);
        if (output_count !== 13) begin
            $display("TEST_FAIL: window_3x3 reset-recovery output_count=%0d expected=13", output_count);
            errors = errors + 1;
        end
        if (errors == 0) $display("TEST_PASS: window_3x3");
        else $fatal(1, "TEST_FAIL: window_3x3 errors=%0d", errors);
        $finish;
    end
endmodule

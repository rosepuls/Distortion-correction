`timescale 1ns/1ps

module tb_gaussian_3x3;
    reg clk = 0, rst_n = 0, in_valid = 0, in_sof = 0, in_eol = 0;
    reg [7:0] p00=0,p01=0,p02=0,p10=0,p11=0,p12=0,p20=0,p21=0,p22=0;
    wire [7:0] out_pixel;
    wire out_valid, out_sof, out_eol;
    integer errors = 0;
    always #5 clk = ~clk;

    gaussian_3x3 dut (.*);

    task apply_and_check;
        input [7:0] a00,a01,a02,a10,a11,a12,a20,a21,a22,expected;
        input sof,eol;
        begin
            @(negedge clk);
            p00=a00;p01=a01;p02=a02;p10=a10;p11=a11;p12=a12;p20=a20;p21=a21;p22=a22;
            in_valid=1;in_sof=sof;in_eol=eol;
            @(negedge clk);
            if (!out_valid || out_pixel!==expected || out_sof!==sof || out_eol!==eol) begin
                $display("TEST_FAIL: gaussian_3x3 got=%0d expected=%0d", out_pixel, expected);
                errors=errors+1;
            end
            in_valid=0;in_sof=0;in_eol=0;
        end
    endtask

    task check_bubble;
        begin
            @(negedge clk); in_valid=0; in_sof=0; in_eol=0;
            @(negedge clk);
            if (out_valid!==0 || out_sof!==0 || out_eol!==0 || out_pixel!==0) begin
                $display("TEST_FAIL: gaussian_3x3 bubble outputs not cleared"); errors=errors+1;
            end
        end
    endtask

    task assert_reset_and_check;
        begin
            rst_n=0; #1;
            if (out_valid!==0 || out_sof!==0 || out_eol!==0 || out_pixel!==0) begin
                $display("TEST_FAIL: gaussian_3x3 reset did not clear outputs"); errors=errors+1;
            end
            in_valid=0; in_sof=0; in_eol=0;
            @(negedge clk); rst_n=1;
        end
    endtask

    initial begin
        repeat(2) @(negedge clk); rst_n=1;
        apply_and_check(0,0,0, 0,255,0, 0,0,0, 63, 1,0);
        apply_and_check(255,255,255, 255,255,255, 255,255,255, 255, 0,1);
        apply_and_check(16,16,16, 16,16,16, 16,16,16, 16, 0,0);
        check_bubble();
        apply_and_check(0,255,0, 255,0,255, 0,255,0, 127, 1,1);
        assert_reset_and_check();
        apply_and_check(255,255,255, 255,255,255, 255,255,255, 255, 1,1);
        check_bubble();
        if(errors==0) $display("TEST_PASS: gaussian_3x3");
        else $fatal(1,"TEST_FAIL: gaussian_3x3 errors=%0d",errors);
        $finish;
    end
endmodule

`timescale 1ns/1ps

module tb_threshold;
    reg clk=0,rst_n=0;
    reg [11:0] in_gradient=0,cfg_threshold=0;
    reg in_valid=0,in_sof=0,in_eol=0;
    wire out_pixel,out_valid,out_sof,out_eol;
    integer errors=0;
    always #5 clk=~clk;

    threshold dut (.*);

    task apply_and_check;
        input [11:0] gradient,level;
        input sof,eol,expected;
        begin
            @(negedge clk);
            in_gradient=gradient;cfg_threshold=level;in_valid=1;in_sof=sof;in_eol=eol;
            @(negedge clk);
            if(!out_valid || out_pixel!==expected || out_sof!==sof || out_eol!==eol) begin
                $display("TEST_FAIL: threshold gradient=%0d got=%0d expected=%0d",gradient,out_pixel,expected);
                errors=errors+1;
            end
            in_valid=0;in_sof=0;in_eol=0;
        end
    endtask

    task check_bubble;
        begin
            @(negedge clk); in_valid=0;in_sof=0;in_eol=0;
            @(negedge clk);
            if(out_valid!==0 || out_sof!==0 || out_eol!==0 || out_pixel!==0) begin
                $display("TEST_FAIL: threshold bubble outputs not cleared");errors=errors+1;
            end
        end
    endtask

    task assert_reset_and_check;
        begin
            rst_n=0;#1;
            if(out_valid!==0 || out_sof!==0 || out_eol!==0 || out_pixel!==0) begin
                $display("TEST_FAIL: threshold reset did not clear outputs");errors=errors+1;
            end
            in_valid=0;in_sof=0;in_eol=0;
            @(negedge clk);rst_n=1;
        end
    endtask

    initial begin
        repeat(2) @(negedge clk);rst_n=1;
        apply_and_check(12'd99,12'd100,1,0,0);
        apply_and_check(12'd100,12'd0,0,0,0);
        apply_and_check(12'd101,12'd0,0,0,1);
        apply_and_check(12'd4095,12'd4095,1,1,0);
        check_bubble();
        apply_and_check(12'd101,12'd100,1,1,1);
        assert_reset_and_check();
        apply_and_check(12'd100,12'd100,1,1,0);
        check_bubble();
        if(errors==0) $display("TEST_PASS: threshold");
        else $fatal(1,"TEST_FAIL: threshold errors=%0d",errors);
        $finish;
    end
endmodule

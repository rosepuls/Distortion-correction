`timescale 1ns/1ps

module tb_morphology;
    reg clk=0,rst_n=0;
    reg p00=0,p01=0,p02=0,p10=0,p11=0,p12=0,p20=0,p21=0,p22=0;
    reg in_valid=0,in_sof=0,in_eol=0,cfg_dilate=0;
    wire out_pixel,out_valid,out_sof,out_eol;
    integer errors=0;
    always #5 clk=~clk;

    morphology dut (.*);

    task apply_and_check;
        input [8:0] bits;
        input dilate,sof,eol,expected;
        begin
            @(negedge clk);
            {p00,p01,p02,p10,p11,p12,p20,p21,p22}=bits;
            cfg_dilate=dilate;in_valid=1;in_sof=sof;in_eol=eol;
            @(negedge clk);
            if(!out_valid || out_pixel!==expected || out_sof!==sof || out_eol!==eol) begin
                $display("TEST_FAIL: morphology bits=%b got=%0d expected=%0d",bits,out_pixel,expected);
                errors=errors+1;
            end
            in_valid=0;in_sof=0;in_eol=0;
        end
    endtask

    task check_bubble;
        begin
            @(negedge clk);in_valid=0;in_sof=0;in_eol=0;
            @(negedge clk);
            if(out_valid!==0 || out_sof!==0 || out_eol!==0 || out_pixel!==0) begin
                $display("TEST_FAIL: morphology bubble outputs not cleared");errors=errors+1;
            end
        end
    endtask

    task assert_reset_and_check;
        begin
            rst_n=0;#1;
            if(out_valid!==0 || out_sof!==0 || out_eol!==0 || out_pixel!==0) begin
                $display("TEST_FAIL: morphology reset did not clear outputs");errors=errors+1;
            end
            in_valid=0;in_sof=0;in_eol=0;
            @(negedge clk);rst_n=1;
        end
    endtask

    initial begin
        repeat(2) @(negedge clk);rst_n=1;
        apply_and_check(9'b000010000,1,1,0,1);
        apply_and_check(9'b000000000,0,0,0,0);
        apply_and_check(9'b111111111,0,1,0,1);
        apply_and_check(9'b111101111,1,0,1,0);
        check_bubble();
        apply_and_check(9'b000000000,1,1,1,0);
        apply_and_check(9'b111111111,0,0,1,1);
        assert_reset_and_check();
        apply_and_check(9'b111111111,1,1,1,1);
        check_bubble();
        if(errors==0) $display("TEST_PASS: morphology");
        else $fatal(1,"TEST_FAIL: morphology errors=%0d",errors);
        $finish;
    end
endmodule

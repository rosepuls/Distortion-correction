`timescale 1ns/1ps

module tb_bilinear_interp;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [23:0] p00 = 0, p10 = 0, p01 = 0, p11 = 0;
    reg [15:0] dx = 0, dy = 0;
    reg coord_valid = 1'b0, in_valid = 1'b0, in_sof = 1'b0, in_eol = 1'b0;
    wire [23:0] out_pixel;
    wire out_valid, out_sof, out_eol;
    integer errors = 0;

    always #5 clk = ~clk;

    bilinear_interp dut (
        .clk(clk), .rst_n(rst_n), .p00(p00), .p10(p10), .p01(p01), .p11(p11),
        .dx(dx), .dy(dy), .coord_valid(coord_valid), .in_valid(in_valid),
        .in_sof(in_sof), .in_eol(in_eol), .out_pixel(out_pixel),
        .out_valid(out_valid), .out_sof(out_sof), .out_eol(out_eol)
    );

    task apply_and_check;
        input [23:0] a, b, c, d;
        input [15:0] fx, fy;
        input coordinate_ok;
        input sof,eol;
        input [23:0] expected;
        begin
            @(negedge clk);
            p00 = a; p10 = b; p01 = c; p11 = d; dx = fx; dy = fy;
            coord_valid = coordinate_ok; in_valid = 1'b1; in_sof=sof; in_eol=eol;
            @(negedge clk);
            if (out_valid !== 1'b0 || out_sof !== 1'b0 || out_eol !== 1'b0) begin
                $display("TEST_FAIL: bilinear_interp must not produce data before its second pipeline stage");
                errors = errors + 1;
            end
            @(negedge clk);
            if (!out_valid || out_pixel !== expected || out_sof!==sof || out_eol!==eol) begin
                $display("TEST_FAIL: bilinear_interp got=%h expected=%h", out_pixel, expected);
                errors = errors + 1;
            end
            in_valid = 1'b0; in_sof=0; in_eol=0;
        end
    endtask

    task check_bubble;
        begin
            @(negedge clk); in_valid=0;in_sof=0;in_eol=0;
            @(negedge clk);
            if(out_valid!==0 || out_sof!==0 || out_eol!==0 || out_pixel!==0) begin
                $display("TEST_FAIL: bilinear_interp bubble outputs not cleared");errors=errors+1;
            end
        end
    endtask

    task assert_reset_and_check;
        begin
            rst_n=0;#1;
            if(out_valid!==0 || out_sof!==0 || out_eol!==0 || out_pixel!==0) begin
                $display("TEST_FAIL: bilinear_interp reset did not clear outputs");errors=errors+1;
            end
            in_valid=0;in_sof=0;in_eol=0;
            @(negedge clk);rst_n=1;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        apply_and_check(24'h646464, 24'hc8c8c8, 24'h323232, 24'h969696,
                        16'h8000, 16'h8000, 1'b1, 1'b1, 1'b0, 24'h7d7d7d);
        apply_and_check(24'h0a141e, 24'h1e2832, 24'h323c46, 24'h46505a,
                        16'h8000, 16'h8000, 1'b1, 1'b0, 1'b0, 24'h28323c);
        apply_and_check(24'hffffff, 24'hffffff, 24'hffffff, 24'hffffff,
                        16'hffff, 16'hffff, 1'b0, 1'b0, 1'b1, 24'h000000);
        // 坐标左上边界 dx=dy=0，结果应严格等于 p00。
        apply_and_check(24'h123456, 24'hffffff, 24'hffffff, 24'h000000,
                        16'h0000, 16'h0000, 1'b1, 1'b1, 1'b1, 24'h123456);
        check_bubble();
        apply_and_check(24'h000000, 24'hffffff, 24'hffffff, 24'hffffff,
                        16'hffff, 16'hffff, 1'b1, 1'b1, 1'b1, 24'hfefefe);
        assert_reset_and_check();
        apply_and_check(24'habcdef, 24'h000000, 24'h000000, 24'h000000,
                        16'h0000, 16'h0000, 1'b1, 1'b1, 1'b1, 24'habcdef);
        check_bubble();
        if (errors == 0) $display("TEST_PASS: bilinear_interp");
        else $fatal(1, "TEST_FAIL: bilinear_interp errors=%0d", errors);
        $finish;
    end
endmodule

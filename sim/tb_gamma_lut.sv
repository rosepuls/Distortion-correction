`timescale 1ns/1ps

module tb_gamma_lut;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [7:0] in_pixel = 8'd0;
    reg in_valid = 1'b0, in_sof = 1'b0, in_eol = 1'b0;
    reg cfg_enable = 1'b0, cfg_bank_select = 1'b0;
    reg cfg_write_enable = 1'b0, cfg_write_bank = 1'b0;
    reg [7:0] cfg_write_address = 8'd0, cfg_write_data = 8'd0;
    wire [7:0] out_pixel;
    wire out_valid, out_sof, out_eol;
    integer errors = 0;

    always #5 clk = ~clk;

    gamma_lut dut (
        .clk(clk), .rst_n(rst_n), .in_pixel(in_pixel), .in_valid(in_valid),
        .in_sof(in_sof), .in_eol(in_eol), .cfg_enable(cfg_enable),
        .cfg_bank_select(cfg_bank_select), .cfg_write_enable(cfg_write_enable),
        .cfg_write_bank(cfg_write_bank), .cfg_write_address(cfg_write_address),
        .cfg_write_data(cfg_write_data), .out_pixel(out_pixel),
        .out_valid(out_valid), .out_sof(out_sof), .out_eol(out_eol)
    );

    task write_lut;
        input bank;
        input [7:0] address;
        input [7:0] data;
        begin
            @(negedge clk);
            cfg_write_enable = 1'b1; cfg_write_bank = bank;
            cfg_write_address = address; cfg_write_data = data;
            @(negedge clk);
            cfg_write_enable = 1'b0;
        end
    endtask

    task apply_and_check;
        input [7:0] pixel;
        input enable_gamma;
        input bank;
        input sof, eol;
        input [7:0] expected;
        begin
            @(negedge clk);
            in_pixel = pixel; cfg_enable = enable_gamma; cfg_bank_select = bank;
            in_valid = 1'b1; in_sof = sof; in_eol = eol;
            @(negedge clk);
            if (!out_valid || out_pixel !== expected || out_sof !== sof || out_eol !== eol) begin
                $display("TEST_FAIL: gamma_lut got=%0d expected=%0d", out_pixel, expected);
                errors = errors + 1;
            end
            in_valid = 1'b0; in_sof = 1'b0; in_eol = 1'b0;
        end
    endtask

    task check_bubble;
        begin
            @(negedge clk); in_valid=0; in_sof=0; in_eol=0;
            @(negedge clk);
            if (out_valid!==0 || out_sof!==0 || out_eol!==0) begin
                $display("TEST_FAIL: gamma_lut bubble control"); errors=errors+1;
            end
        end
    endtask

    task assert_reset_and_check;
        begin
            rst_n=0; #1;
            if (out_valid!==0 || out_sof!==0 || out_eol!==0 || out_pixel!==0) begin
                $display("TEST_FAIL: gamma_lut reset did not clear outputs"); errors=errors+1;
            end
            in_valid=0; in_sof=0; in_eol=0;
            @(negedge clk); rst_n=1;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        write_lut(1'b0, 8'd5, 8'd42);
        write_lut(1'b1, 8'd5, 8'd99);
        apply_and_check(8'd5, 1'b1, 1'b0, 1'b1, 1'b0, 8'd42);
        // 帧内切换 bank 配置不能影响当前帧锁存值。
        apply_and_check(8'd5, 1'b1, 1'b1, 1'b0, 1'b1, 8'd42);
        apply_and_check(8'd5, 1'b1, 1'b1, 1'b1, 1'b1, 8'd99);
        apply_and_check(8'd5, 1'b0, 1'b0, 1'b1, 1'b0, 8'd5);
        check_bubble();
        // 新帧从 bank1 查表；复位后默认旁路应立即生效。
        apply_and_check(8'd5, 1'b1, 1'b1, 1'b1, 1'b1, 8'd99);
        assert_reset_and_check();
        apply_and_check(8'd5, 1'b0, 1'b0, 1'b1, 1'b1, 8'd5);
        check_bubble();
        if (errors == 0) $display("TEST_PASS: gamma_lut");
        else $fatal(1, "TEST_FAIL: gamma_lut errors=%0d", errors);
        $finish;
    end
endmodule

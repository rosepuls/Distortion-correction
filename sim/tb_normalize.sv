`timescale 1ns/1ps

// Catches wrong Q13.19 x Q2.30 scaling, sign extension, and arithmetic
// right-shift truncation in the stateless normalize stage.
module tb_normalize;
    reg signed [31:0] centered_x_q19;
    reg signed [31:0] centered_y_q19;
    reg signed [31:0] inv_fx_q30;
    reg signed [31:0] inv_fy_q30;
    wire signed [31:0] x_q28;
    wire signed [31:0] y_q28;
    integer errors = 0;

    normalize dut (
        .centered_x_q19(centered_x_q19), .centered_y_q19(centered_y_q19),
        .inv_fx_q30(inv_fx_q30), .inv_fy_q30(inv_fy_q30), .x_q28(x_q28), .y_q28(y_q28)
    );

    task automatic check_case;
        input signed [31:0] cx;
        input signed [31:0] cy;
        input signed [31:0] ifx;
        input signed [31:0] ify;
        input signed [31:0] expected_x;
        input signed [31:0] expected_y;
        begin
            centered_x_q19 = cx; centered_y_q19 = cy;
            inv_fx_q30 = ifx; inv_fy_q30 = ify;
            #1;
            if (x_q28 !== expected_x || y_q28 !== expected_y) begin
                $display("TEST_FAIL: normalize got (%0d,%0d), expected (%0d,%0d)", x_q28, y_q28, expected_x, expected_y);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // +0.5 Q13.19 times +0.5 Q2.30 equals +0.25 Q4.28.
        check_case(32'sd262144, -32'sd262144, 32'sd536870912, 32'sd536870912,
                   32'sd67108864, -32'sd67108864);
        // A negative reciprocal must retain its sign.
        check_case(32'sd262144, -32'sd262144, -32'sd1073741824, -32'sd1073741824,
                   -32'sd134217728, 32'sd134217728);
        // Arithmetic truncation: -1 LSB product rounds down to -1, +1 to 0.
        check_case(32'sd1, 32'sd1, 32'sd1, -32'sd1, 32'sd0, -32'sd1);
        if (errors == 0) $display("TEST_PASS: normalize");
        else $fatal(1, "TEST_FAIL: normalize errors=%0d", errors);
        $finish;
    end
endmodule

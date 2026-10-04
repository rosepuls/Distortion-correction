`timescale 1ns/1ps

// Fixed-point coordinate normalization.
// centered_* is signed Q13.19, inv_f* is signed Q2.30, and x/y is signed
// Q4.28.  19 + 30 - 28 = 21, so the reduction is an arithmetic >> 21.
module normalize (
    input  wire signed [31:0] centered_x_q19,
    input  wire signed [31:0] centered_y_q19,
    input  wire signed [31:0] inv_fx_q30,
    input  wire signed [31:0] inv_fy_q30,
    output wire signed [31:0] x_q28,
    output wire signed [31:0] y_q28
);

    wire signed [63:0] x_product_q49;
    wire signed [63:0] y_product_q49;

    assign x_product_q49 = centered_x_q19 * inv_fx_q30;
    assign y_product_q49 = centered_y_q19 * inv_fy_q30;
    assign x_q28 = x_product_q49 >>> 21;
    assign y_q28 = y_product_q49 >>> 21;

endmodule

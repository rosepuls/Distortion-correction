`timescale 1ns/1ps

// Splits signed Q13.19 source coordinates for bilinear interpolation.
// Arithmetic right shift implements mathematical floor for negative values.
// The three discarded low bits convert the non-negative Q0.19 fraction to
// an unsigned Q0.16 fraction by truncation.
module coordinate_split #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720
) (
    input  wire signed [63:0] src_x_q19,
    input  wire signed [63:0] src_y_q19,
    output wire signed [31:0] x0,
    output wire signed [31:0] y0,
    output wire        [15:0] dx_q16,
    output wire        [15:0] dy_q16,
    output wire               coord_valid
);

    localparam signed [31:0] LAST_X = IMAGE_WIDTH - 1;
    localparam signed [31:0] LAST_Y = IMAGE_HEIGHT - 1;

    assign x0 = src_x_q19 >>> 19;
    assign y0 = src_y_q19 >>> 19;
    assign dx_q16 = src_x_q19[18:3];
    assign dy_q16 = src_y_q19[18:3];
    assign coord_valid = (x0 >= 0) && (x0 < LAST_X) &&
                         (y0 >= 0) && (y0 < LAST_Y);

endmodule

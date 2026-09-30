`timescale 1ns/1ps

// Catches an incorrect floor, fractional extraction, or four-neighbour
// boundary decision in the stateless Q13.19 coordinate splitter.
module tb_coordinate_split;
    localparam integer IMAGE_WIDTH = 4;
    localparam integer IMAGE_HEIGHT = 3;
    reg signed [63:0] src_x_q19;
    reg signed [63:0] src_y_q19;
    wire signed [31:0] x0, y0;
    wire [15:0] dx_q16, dy_q16;
    wire coord_valid;
    integer errors = 0;

    coordinate_split #(.IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT)) dut (
        .src_x_q19(src_x_q19), .src_y_q19(src_y_q19), .x0(x0), .y0(y0),
        .dx_q16(dx_q16), .dy_q16(dy_q16), .coord_valid(coord_valid)
    );

    task automatic check_case;
        input signed [63:0] src_x;
        input signed [63:0] src_y;
        input signed [31:0] expected_x0;
        input signed [31:0] expected_y0;
        input [15:0] expected_dx;
        input [15:0] expected_dy;
        input expected_valid;
        begin
            src_x_q19 = src_x; src_y_q19 = src_y; #1;
            if (x0 !== expected_x0 || y0 !== expected_y0 || dx_q16 !== expected_dx ||
                dy_q16 !== expected_dy || coord_valid !== expected_valid) begin
                $display("TEST_FAIL: coordinate_split got xy=(%0d,%0d) d=(%h,%h) valid=%b", x0, y0, dx_q16, dy_q16, coord_valid);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // Interior coordinate (2.5, 1.25): all four bilinear neighbours exist.
        check_case(64'sd1310720, 64'sd655360, 32'sd2, 32'sd1, 16'h8000, 16'h4000, 1'b1);
        // Negative values require mathematical floor, not truncation toward zero.
        check_case(-64'sd131072, -64'sd1, -32'sd1, -32'sd1, 16'hc000, 16'hffff, 1'b0);
        // Right and bottom edges lack the x0+1/y0+1 neighbour.
        check_case(64'sd1572864, 64'sd0, 32'sd3, 32'sd0, 16'h0000, 16'h0000, 1'b0);
        check_case(64'sd0, 64'sd1048576, 32'sd0, 32'sd2, 16'h0000, 16'h0000, 1'b0);
        if (errors == 0) $display("TEST_PASS: coordinate_split");
        else $fatal(1, "TEST_FAIL: coordinate_split errors=%0d", errors);
        $finish;
    end
endmodule

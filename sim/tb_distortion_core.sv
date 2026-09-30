`timescale 1ns/1ps

// End-to-end testbench for coordinate_gen -> distortion_core.
// Core delay is five registered stages; coordinate_gen contributes one stage.
module tb_distortion_core;
    localparam integer IMAGE_WIDTH = 4;
    localparam integer IMAGE_HEIGHT = 3;
    localparam integer TOTAL_LATENCY = 6;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg in_sof = 1'b0;
    reg in_eol = 1'b0;

    reg signed [31:0] cfg_fx_q19 = 32'sd0;
    reg signed [31:0] cfg_fy_q19 = 32'sd0;
    reg signed [31:0] cfg_cx_q19 = 32'sd0;
    reg signed [31:0] cfg_cy_q19 = 32'sd0;
    reg signed [31:0] cfg_inv_fx_q30 = 32'sd0;
    reg signed [31:0] cfg_inv_fy_q30 = 32'sd0;
    reg signed [31:0] cfg_k1_q28 = 32'sd0;
    reg signed [31:0] cfg_k2_q28 = 32'sd0;
    reg signed [31:0] cfg_p1_q28 = 32'sd0;
    reg signed [31:0] cfg_p2_q28 = 32'sd0;

    wire [12:0] gen_u;
    wire [12:0] gen_v;
    wire gen_valid;
    wire gen_sof;
    wire gen_eol;

    wire signed [63:0] out_src_x_q19;
    wire signed [63:0] out_src_y_q19;
    wire signed [31:0] out_x0;
    wire signed [31:0] out_y0;
    wire [15:0] out_dx_q16;
    wire [15:0] out_dy_q16;
    wire out_coord_valid;
    wire out_valid;
    wire out_sof;
    wire out_eol;

    reg signed [31:0] norm_centered_x_q19 = 32'sd0;
    reg signed [31:0] norm_centered_y_q19 = 32'sd0;
    reg signed [31:0] norm_inv_fx_q30 = 32'sd0;
    reg signed [31:0] norm_inv_fy_q30 = 32'sd0;
    wire signed [31:0] norm_x_q28;
    wire signed [31:0] norm_y_q28;

    reg signed [63:0] split_src_x_q19 = 64'sd0;
    reg signed [63:0] split_src_y_q19 = 64'sd0;
    wire signed [31:0] split_x0;
    wire signed [31:0] split_y0;
    wire [15:0] split_dx_q16;
    wire [15:0] split_dy_q16;
    wire split_coord_valid;

    integer errors = 0;

    always #5 clk = ~clk;

    coordinate_gen #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .COORD_WIDTH(13)
    ) coordinate_gen_dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_sof(in_sof),
        .in_eol(in_eol),
        .out_u(gen_u),
        .out_v(gen_v),
        .out_valid(gen_valid),
        .out_sof(gen_sof),
        .out_eol(gen_eol)
    );

    normalize normalize_dut (
        .centered_x_q19(norm_centered_x_q19),
        .centered_y_q19(norm_centered_y_q19),
        .inv_fx_q30(norm_inv_fx_q30),
        .inv_fy_q30(norm_inv_fy_q30),
        .x_q28(norm_x_q28),
        .y_q28(norm_y_q28)
    );

    coordinate_split #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) coordinate_split_dut (
        .src_x_q19(split_src_x_q19),
        .src_y_q19(split_src_y_q19),
        .x0(split_x0),
        .y0(split_y0),
        .dx_q16(split_dx_q16),
        .dy_q16(split_dy_q16),
        .coord_valid(split_coord_valid)
    );

    distortion_core #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .COORD_WIDTH(13)
    ) distortion_core_dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_u(gen_u),
        .in_v(gen_v),
        .in_valid(gen_valid),
        .in_sof(gen_sof),
        .in_eol(gen_eol),
        .cfg_fx_q19(cfg_fx_q19),
        .cfg_fy_q19(cfg_fy_q19),
        .cfg_cx_q19(cfg_cx_q19),
        .cfg_cy_q19(cfg_cy_q19),
        .cfg_inv_fx_q30(cfg_inv_fx_q30),
        .cfg_inv_fy_q30(cfg_inv_fy_q30),
        .cfg_k1_q28(cfg_k1_q28),
        .cfg_k2_q28(cfg_k2_q28),
        .cfg_p1_q28(cfg_p1_q28),
        .cfg_p2_q28(cfg_p2_q28),
        .out_src_x_q19(out_src_x_q19),
        .out_src_y_q19(out_src_y_q19),
        .out_x0(out_x0),
        .out_y0(out_y0),
        .out_dx_q16(out_dx_q16),
        .out_dy_q16(out_dy_q16),
        .out_coord_valid(out_coord_valid),
        .out_valid(out_valid),
        .out_sof(out_sof),
        .out_eol(out_eol)
    );

    task automatic set_camera;
        input signed [31:0] fx_q19;
        input signed [31:0] fy_q19;
        input signed [31:0] cx_q19;
        input signed [31:0] cy_q19;
        input signed [31:0] inv_fx_q30;
        input signed [31:0] inv_fy_q30;
        input signed [31:0] k1_q28;
        input signed [31:0] k2_q28;
        input signed [31:0] p1_q28;
        input signed [31:0] p2_q28;
        begin
            cfg_fx_q19 = fx_q19;
            cfg_fy_q19 = fy_q19;
            cfg_cx_q19 = cx_q19;
            cfg_cy_q19 = cy_q19;
            cfg_inv_fx_q30 = inv_fx_q30;
            cfg_inv_fy_q30 = inv_fy_q30;
            cfg_k1_q28 = k1_q28;
            cfg_k2_q28 = k2_q28;
            cfg_p1_q28 = p1_q28;
            cfg_p2_q28 = p2_q28;
        end
    endtask

    task automatic send_and_check;
        input sof;
        input eol;
        input signed [63:0] expected_src_x_q19;
        input signed [63:0] expected_src_y_q19;
        input signed [31:0] expected_x0;
        input signed [31:0] expected_y0;
        input [15:0] expected_dx_q16;
        input [15:0] expected_dy_q16;
        input expected_coord_valid;
        begin
            @(negedge clk);
            in_valid = 1'b1;
            in_sof = sof;
            in_eol = eol;
            @(negedge clk);
            in_valid = 1'b0;
            in_sof = 1'b0;
            in_eol = 1'b0;
            repeat (TOTAL_LATENCY - 1) @(negedge clk);
            if (out_valid !== 1'b1 ||
                out_src_x_q19 !== expected_src_x_q19 ||
                out_src_y_q19 !== expected_src_y_q19 ||
                out_x0 !== expected_x0 || out_y0 !== expected_y0 ||
                out_dx_q16 !== expected_dx_q16 || out_dy_q16 !== expected_dy_q16 ||
                out_coord_valid !== expected_coord_valid ||
                out_sof !== sof || out_eol !== eol) begin
                $display("TEST_FAIL: distortion result got src=(%0d,%0d) xy=(%0d,%0d) d=(%h,%h) valid=%b sof=%b eol=%b",
                         out_src_x_q19, out_src_y_q19, out_x0, out_y0,
                         out_dx_q16, out_dy_q16, out_coord_valid, out_sof, out_eol);
                errors = errors + 1;
            end
            @(negedge clk);
            if (out_valid !== 1'b0 || out_sof !== 1'b0 || out_eol !== 1'b0) begin
                $display("TEST_FAIL: distortion pipeline did not clear after bubble");
                errors = errors + 1;
            end
        end
    endtask

    task automatic check_scalar_helpers;
        begin
            norm_centered_x_q19 = 32'sd524288;
            norm_centered_y_q19 = -32'sd524288;
            norm_inv_fx_q30 = 32'sd536870912;
            norm_inv_fy_q30 = 32'sd536870912;
            #1;
            if (norm_x_q28 !== 32'sd134217728 || norm_y_q28 !== -32'sd134217728) begin
                $display("TEST_FAIL: normalize Q13.19 x Q2.30 to Q4.28 is incorrect");
                errors = errors + 1;
            end

            split_src_x_q19 = -64'sd131072;
            split_src_y_q19 = 64'sd0;
            #1;
            if (split_x0 !== -32'sd1 || split_y0 !== 32'sd0 ||
                split_dx_q16 !== 16'hc000 || split_dy_q16 !== 16'h0000 ||
                split_coord_valid !== 1'b0) begin
                $display("TEST_FAIL: coordinate_split negative floor is incorrect");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        check_scalar_helpers();
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // New frame: fx=fy=1, k1=1. Output u=0 is the optical center.
        set_camera(32'sd524288, 32'sd524288, 32'sd0, 32'sd0,
                   32'sd1073741824, 32'sd1073741824,
                   32'sd268435456, 32'sd0, 32'sd0, 32'sd0);
        send_and_check(1'b1, 1'b0, 64'sd0, 64'sd0,
                       32'sd0, 32'sd0, 16'h0000, 16'h0000, 1'b1);

        // u=1 under k1=1 maps to src_x=2.0 pixels.
        send_and_check(1'b0, 1'b0, 64'sd1048576, 64'sd0,
                       32'sd2, 32'sd0, 16'h0000, 16'h0000, 1'b1);

        // Mid-frame configuration changes must not affect the latched k1=1 frame.
        set_camera(32'sd524288, 32'sd524288, 32'sd0, 32'sd0,
                   32'sd1073741824, 32'sd1073741824,
                   32'sd0, 32'sd0, 32'sd0, 32'sd134217728);
        send_and_check(1'b0, 1'b0, 64'sd5242880, 64'sd0,
                       32'sd10, 32'sd0, 16'h0000, 16'h0000, 1'b0);

        // A new sof latches p2=0.5; u=1 then maps to src_x=2.5 pixels.
        send_and_check(1'b1, 1'b0, 64'sd0, 64'sd0,
                       32'sd0, 32'sd0, 16'h0000, 16'h0000, 1'b1);
        send_and_check(1'b0, 1'b1, 64'sd1310720, 64'sd0,
                       32'sd2, 32'sd0, 16'h8000, 16'h0000, 1'b1);

        rst_n = 1'b0;
        #1;
        if (out_valid !== 1'b0 || out_sof !== 1'b0 || out_eol !== 1'b0) begin
            $display("TEST_FAIL: reset did not clear distortion outputs");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TEST_PASS: distortion_core");
        else
            $fatal(1, "TEST_FAIL: distortion_core errors=%0d", errors);
        $finish;
    end
endmodule

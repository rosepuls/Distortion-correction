`timescale 1ns/1ps

// Catches a broken coordinate counter, SOF re-alignment, EOL wrap, or a
// stale control output during an input bubble/reset.
module tb_coordinate_gen;
    localparam integer IMAGE_WIDTH = 3;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg in_sof = 1'b0;
    reg in_eol = 1'b0;
    wire [12:0] out_u, out_v;
    wire out_valid, out_sof, out_eol;
    integer errors = 0;

    always #5 clk = ~clk;

    coordinate_gen #(.IMAGE_WIDTH(IMAGE_WIDTH), .COORD_WIDTH(13)) dut (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .in_sof(in_sof), .in_eol(in_eol), .out_u(out_u), .out_v(out_v),
        .out_valid(out_valid), .out_sof(out_sof), .out_eol(out_eol)
    );

    task automatic send_and_check;
        input valid;
        input sof;
        input eol;
        input [12:0] expected_u;
        input [12:0] expected_v;
        begin
            @(negedge clk);
            in_valid = valid; in_sof = sof; in_eol = eol;
            @(posedge clk); #1;
            if (valid) begin
                if (out_valid !== 1'b1 || out_u !== expected_u || out_v !== expected_v ||
                    out_sof !== sof || out_eol !== eol) begin
                    $display("TEST_FAIL: coordinate_gen got uv=(%0d,%0d) ctrl=%b%b%b", out_u, out_v, out_valid, out_sof, out_eol);
                    errors = errors + 1;
                end
            end else if (out_valid !== 1'b0 || out_sof !== 1'b0 || out_eol !== 1'b0 ||
                         out_u !== 13'd0 || out_v !== 13'd0) begin
                $display("TEST_FAIL: coordinate_gen bubble did not clear outputs");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        if (out_valid !== 1'b0 || out_sof !== 1'b0 || out_eol !== 1'b0 || out_u !== 0 || out_v !== 0) begin
            $display("TEST_FAIL: coordinate_gen reset did not clear outputs");
            errors = errors + 1;
        end
        rst_n = 1'b1;

        // Two full 3x2 frames are contiguous at the frame boundary.
        send_and_check(1,1,0, 0,0); send_and_check(1,0,0, 1,0); send_and_check(1,0,1, 2,0);
        send_and_check(1,0,0, 0,1); send_and_check(1,0,0, 1,1); send_and_check(1,0,1, 2,1);
        send_and_check(1,1,0, 0,0); send_and_check(1,0,0, 1,0); send_and_check(1,0,1, 2,0);
        send_and_check(1,0,0, 0,1); send_and_check(1,0,0, 1,1); send_and_check(1,0,1, 2,1);

        send_and_check(0,0,0, 0,0);
        // A new SOF must override an unfinished previous line/frame.
        send_and_check(1,0,0, 0,2);
        send_and_check(1,1,0, 0,0);

        rst_n = 1'b0; #1;
        if (out_valid !== 1'b0 || out_sof !== 1'b0 || out_eol !== 1'b0 || out_u !== 0 || out_v !== 0) begin
            $display("TEST_FAIL: coordinate_gen asynchronous reset did not clear outputs");
            errors = errors + 1;
        end
        rst_n = 1'b1;
        send_and_check(1,1,1, 0,0);

        if (errors == 0) $display("TEST_PASS: coordinate_gen");
        else $fatal(1, "TEST_FAIL: coordinate_gen errors=%0d", errors);
        $finish;
    end
endmodule

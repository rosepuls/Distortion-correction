`timescale 1ns/1ps

// Streaming regression for the new coordinate chain.  It catches a missing
// valid/control delay, counter movement on bubbles, SOF frame re-lock, and
// last-row/last-column bilinear boundary handling.
module tb_distortion_stream;
    localparam integer IMAGE_WIDTH = 4;
    localparam integer IMAGE_HEIGHT = 3;
    localparam integer PIPE_DELAY = 5;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg in_valid = 1'b0, in_sof = 1'b0, in_eol = 1'b0;
    reg signed [31:0] cfg_fx_q19, cfg_fy_q19, cfg_cx_q19, cfg_cy_q19;
    reg signed [31:0] cfg_inv_fx_q30, cfg_inv_fy_q30, cfg_k1_q28, cfg_k2_q28, cfg_p1_q28, cfg_p2_q28;
    wire [12:0] gen_u, gen_v;
    wire gen_valid, gen_sof, gen_eol;
    wire signed [63:0] out_src_x_q19, out_src_y_q19;
    wire signed [31:0] out_x0, out_y0;
    wire [15:0] out_dx_q16, out_dy_q16;
    wire out_coord_valid, out_valid, out_sof, out_eol;
    reg valid_pipe [0:PIPE_DELAY-1];
    reg sof_pipe [0:PIPE_DELAY-1];
    reg eol_pipe [0:PIPE_DELAY-1];
    integer u_pipe [0:PIPE_DELAY-1];
    integer v_pipe [0:PIPE_DELAY-1];
    integer model_u = 0, model_v = 0, i, errors = 0;
    reg monitor_enabled = 1'b0;

    always #5 clk = ~clk;

    coordinate_gen #(.IMAGE_WIDTH(IMAGE_WIDTH), .COORD_WIDTH(13)) gen (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_sof(in_sof), .in_eol(in_eol),
        .out_u(gen_u), .out_v(gen_v), .out_valid(gen_valid), .out_sof(gen_sof), .out_eol(gen_eol)
    );
    distortion_core #(.IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT), .COORD_WIDTH(13)) core (
        .clk(clk), .rst_n(rst_n), .in_u(gen_u), .in_v(gen_v), .in_valid(gen_valid), .in_sof(gen_sof), .in_eol(gen_eol),
        .cfg_fx_q19(cfg_fx_q19), .cfg_fy_q19(cfg_fy_q19), .cfg_cx_q19(cfg_cx_q19), .cfg_cy_q19(cfg_cy_q19),
        .cfg_inv_fx_q30(cfg_inv_fx_q30), .cfg_inv_fy_q30(cfg_inv_fy_q30), .cfg_k1_q28(cfg_k1_q28), .cfg_k2_q28(cfg_k2_q28),
        .cfg_p1_q28(cfg_p1_q28), .cfg_p2_q28(cfg_p2_q28),
        .out_src_x_q19(out_src_x_q19), .out_src_y_q19(out_src_y_q19), .out_x0(out_x0), .out_y0(out_y0),
        .out_dx_q16(out_dx_q16), .out_dy_q16(out_dy_q16), .out_coord_valid(out_coord_valid),
        .out_valid(out_valid), .out_sof(out_sof), .out_eol(out_eol)
    );

    always @(negedge rst_n) begin
        model_u = 0; model_v = 0;
        for (i = 0; i < PIPE_DELAY; i = i + 1) begin
            valid_pipe[i] = 1'b0; sof_pipe[i] = 1'b0; eol_pipe[i] = 1'b0; u_pipe[i] = 0; v_pipe[i] = 0;
        end
    end

    always @(posedge clk) begin
        #1;
        if (monitor_enabled) begin
            if (valid_pipe[PIPE_DELAY-1]) begin
                if (out_valid !== 1'b1 || out_src_x_q19 !== u_pipe[PIPE_DELAY-1] * 524288 ||
                    out_src_y_q19 !== v_pipe[PIPE_DELAY-1] * 524288 || out_x0 !== u_pipe[PIPE_DELAY-1] ||
                    out_y0 !== v_pipe[PIPE_DELAY-1] || out_dx_q16 !== 16'd0 || out_dy_q16 !== 16'd0 ||
                    out_coord_valid !== ((u_pipe[PIPE_DELAY-1] < IMAGE_WIDTH-1) && (v_pipe[PIPE_DELAY-1] < IMAGE_HEIGHT-1)) ||
                    out_sof !== sof_pipe[PIPE_DELAY-1] || out_eol !== eol_pipe[PIPE_DELAY-1]) begin
                    $display("TEST_FAIL: stream result/control misalignment"); errors = errors + 1;
                end
            end else if (out_valid !== 1'b0 || out_sof !== 1'b0 || out_eol !== 1'b0) begin
                $display("TEST_FAIL: stream bubble created a stale valid/control output"); errors = errors + 1;
            end
            for (i = PIPE_DELAY-1; i > 0; i = i - 1) begin
                valid_pipe[i] = valid_pipe[i-1]; sof_pipe[i] = sof_pipe[i-1]; eol_pipe[i] = eol_pipe[i-1];
                u_pipe[i] = u_pipe[i-1]; v_pipe[i] = v_pipe[i-1];
            end
            valid_pipe[0] = in_valid; sof_pipe[0] = in_valid && in_sof; eol_pipe[0] = in_valid && in_eol;
            if (in_valid) begin
                if (in_sof) begin
                    u_pipe[0] = 0; v_pipe[0] = 0; model_u = 1; model_v = 0;
                end else begin
                    u_pipe[0] = model_u; v_pipe[0] = model_v;
                    if (in_eol) begin model_u = 0; model_v = model_v + 1; end
                    else model_u = model_u + 1;
                end
            end else begin
                u_pipe[0] = 0; v_pipe[0] = 0;
            end
        end
    end

    task automatic drive;
        input valid; input sof; input eol;
        begin
            @(negedge clk); in_valid = valid; in_sof = sof; in_eol = eol;
        end
    endtask

    task automatic drive_identity_frame;
        integer x, y;
        begin
            for (y = 0; y < IMAGE_HEIGHT; y = y + 1)
                for (x = 0; x < IMAGE_WIDTH; x = x + 1) begin
                    drive(1'b1, (x == 0 && y == 0), (x == IMAGE_WIDTH-1));
                    // A mid-frame invalid cycle must not advance the coordinate model.
                    if (x == 1 && y == 1) drive(1'b0, 1'b0, 1'b0);
                end
        end
    endtask

    initial begin
        cfg_fx_q19 = 32'sd524288; cfg_fy_q19 = 32'sd524288; cfg_cx_q19 = 0; cfg_cy_q19 = 0;
        cfg_inv_fx_q30 = 32'sd1073741824; cfg_inv_fy_q30 = 32'sd1073741824;
        cfg_k1_q28 = 0; cfg_k2_q28 = 0; cfg_p1_q28 = 0; cfg_p2_q28 = 0;
        repeat (2) @(negedge clk); rst_n = 1'b1; monitor_enabled = 1'b1;

        // No bubble is inserted between the first frame's final pixel and the second SOF.
        drive_identity_frame();
        drive_identity_frame();
        repeat (PIPE_DELAY + 2) @(negedge clk);

        rst_n = 1'b0; #1;
        if (out_valid !== 1'b0 || out_sof !== 1'b0 || out_eol !== 1'b0) begin
            $display("TEST_FAIL: stream reset did not clear outputs"); errors = errors + 1;
        end
        rst_n = 1'b1;
        drive(1'b1, 1'b1, 1'b1);
        repeat (PIPE_DELAY + 2) @(negedge clk);

        if (errors == 0) $display("TEST_PASS: distortion_stream");
        else $fatal(1, "TEST_FAIL: distortion_stream errors=%0d", errors);
        $finish;
    end
endmodule

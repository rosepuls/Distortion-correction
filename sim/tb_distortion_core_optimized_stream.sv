`timescale 1ns/1ps

module tb_distortion_core_optimized_stream;
    // The two partial-product stages before Stage 1 add two cycles.
    localparam integer PIPELINE_LATENCY = 15;
    localparam integer DRIVE_CYCLES = 10;
    localparam integer TOTAL_CYCLES = DRIVE_CYCLES + PIPELINE_LATENCY;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [12:0] in_u = 13'd0;
    reg [12:0] in_v = 13'd0;
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

    reg [12:0] vector_u [0:DRIVE_CYCLES-1];
    reg [12:0] vector_v [0:DRIVE_CYCLES-1];
    reg vector_valid [0:DRIVE_CYCLES-1];
    reg vector_sof [0:DRIVE_CYCLES-1];
    reg vector_eol [0:DRIVE_CYCLES-1];

    integer cycle_index;
    integer expected_index;
    integer error_count = 0;
    integer checked_count = 0;
    reg signed [63:0] expected_x_q19;
    reg signed [63:0] expected_y_q19;

    always #5 clk = ~clk;

    distortion_core_optimized #(
        .IMAGE_WIDTH(1280),
        .IMAGE_HEIGHT(720),
        .COORD_WIDTH(13)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_u(in_u),
        .in_v(in_v),
        .in_valid(in_valid),
        .in_sof(in_sof),
        .in_eol(in_eol),
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

    task set_frame0_config;
        begin
            // fx=fy=512, cx=cy=0, inverse=1/512.  This is exactly
            // representable through every Q-format conversion and maps u/v
            // back to themselves.
            cfg_fx_q19 = 32'sd268435456;
            cfg_fy_q19 = 32'sd268435456;
            cfg_cx_q19 = 32'sd0;
            cfg_cy_q19 = 32'sd0;
            cfg_inv_fx_q30 = 32'sd2097152;
            cfg_inv_fy_q30 = 32'sd2097152;
            cfg_k1_q28 = 32'sd0;
            cfg_k2_q28 = 32'sd0;
            cfg_p1_q28 = 32'sd0;
            cfg_p2_q28 = 32'sd0;
        end
    endtask

    task set_frame1_config;
        begin
            // A different exactly representable identity calibration proves
            // that SOF selects a new frame-stable parameter set.
            cfg_fx_q19 = 32'sd134217728;
            cfg_fy_q19 = 32'sd134217728;
            cfg_cx_q19 = 32'sd8388608;
            cfg_cy_q19 = 32'sd4194304;
            cfg_inv_fx_q30 = 32'sd4194304;
            cfg_inv_fy_q30 = 32'sd4194304;
            cfg_k1_q28 = 32'sd0;
            cfg_k2_q28 = 32'sd0;
            cfg_p1_q28 = 32'sd0;
            cfg_p2_q28 = 32'sd0;
        end
    endtask

    task check_cycle;
        input integer index;
        begin
            if (index >= 0 && index < DRIVE_CYCLES && vector_valid[index]) begin
                expected_x_q19 = $signed({1'b0, vector_u[index]}) <<< 19;
                expected_y_q19 = $signed({1'b0, vector_v[index]}) <<< 19;
                checked_count = checked_count + 1;
                if (out_valid !== 1'b1 ||
                    out_sof !== vector_sof[index] ||
                    out_eol !== vector_eol[index] ||
                    out_src_x_q19 !== expected_x_q19 ||
                    out_src_y_q19 !== expected_y_q19 ||
                    out_x0 !== $signed({1'b0, vector_u[index]}) ||
                    out_y0 !== $signed({1'b0, vector_v[index]}) ||
                    out_dx_q16 !== 16'd0 ||
                    out_dy_q16 !== 16'd0 ||
                    out_coord_valid !== 1'b1) begin
                    $display("STREAM_MISMATCH index=%0d valid=%b sof=%b eol=%b src=(%0d,%0d) split=(%0d,%0d,%0d,%0d,%b)",
                             index, out_valid, out_sof, out_eol,
                             out_src_x_q19, out_src_y_q19,
                             out_x0, out_y0, out_dx_q16, out_dy_q16,
                             out_coord_valid);
                    error_count = error_count + 1;
                end
            end else begin
                if (out_valid !== 1'b0 || out_sof !== 1'b0 ||
                    out_eol !== 1'b0 || out_coord_valid !== 1'b0 ||
                    out_src_x_q19 !== 64'sd0 ||
                    out_src_y_q19 !== 64'sd0 ||
                    out_x0 !== 32'sd0 || out_y0 !== 32'sd0 ||
                    out_dx_q16 !== 16'd0 || out_dy_q16 !== 16'd0) begin
                    $display("STREAM_BUBBLE_MISMATCH index=%0d valid=%b sof=%b eol=%b",
                             index, out_valid, out_sof, out_eol);
                    error_count = error_count + 1;
                end
            end
        end
    endtask

    initial begin
        for (cycle_index = 0; cycle_index < DRIVE_CYCLES;
             cycle_index = cycle_index + 1) begin
            vector_u[cycle_index] = 13'd0;
            vector_v[cycle_index] = 13'd0;
            vector_valid[cycle_index] = 1'b0;
            vector_sof[cycle_index] = 1'b0;
            vector_eol[cycle_index] = 1'b0;
        end

        vector_u[0] = 13'd10; vector_v[0] = 13'd20;
        vector_valid[0] = 1'b1; vector_sof[0] = 1'b1;
        vector_u[1] = 13'd11; vector_v[1] = 13'd20;
        vector_valid[1] = 1'b1;
        vector_u[2] = 13'd12; vector_v[2] = 13'd20;
        vector_valid[2] = 1'b1; vector_eol[2] = 1'b1;
        // Cycle 3 is an intentional bubble.
        vector_u[4] = 13'd13; vector_v[4] = 13'd21;
        vector_valid[4] = 1'b1;
        // Cycle 5 is an intentional bubble.
        vector_u[6] = 13'd40; vector_v[6] = 13'd30;
        vector_valid[6] = 1'b1; vector_sof[6] = 1'b1;
        vector_u[7] = 13'd41; vector_v[7] = 13'd30;
        vector_valid[7] = 1'b1;
        vector_u[8] = 13'd42; vector_v[8] = 13'd30;
        vector_valid[8] = 1'b1; vector_eol[8] = 1'b1;
        // Cycle 9 is an intentional bubble.

        set_frame0_config();
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        for (cycle_index = 0; cycle_index < TOTAL_CYCLES;
             cycle_index = cycle_index + 1) begin
            @(negedge clk);
            if (cycle_index == 6)
                set_frame1_config();

            if (cycle_index < DRIVE_CYCLES) begin
                in_u = vector_u[cycle_index];
                in_v = vector_v[cycle_index];
                in_valid = vector_valid[cycle_index];
                in_sof = vector_sof[cycle_index];
                in_eol = vector_eol[cycle_index];
            end else begin
                in_u = 13'd0;
                in_v = 13'd0;
                in_valid = 1'b0;
                in_sof = 1'b0;
                in_eol = 1'b0;
            end

            @(posedge clk);
            #1;
            expected_index = cycle_index - (PIPELINE_LATENCY - 1);
            check_cycle(expected_index);
        end

        @(negedge clk);
        rst_n = 1'b0;
        #1;
        if (out_valid !== 1'b0 || out_coord_valid !== 1'b0 ||
            out_src_x_q19 !== 64'sd0 || out_src_y_q19 !== 64'sd0)
            error_count = error_count + 1;

        if (checked_count != 7)
            $fatal(1, "TEST_FAIL: expected 7 streamed coordinates, checked %0d",
                   checked_count);
        if (error_count != 0)
            $fatal(1, "TEST_FAIL: distortion_core_optimized_stream errors=%0d",
                   error_count);

        $display("TEST_PASS: distortion_core_optimized_stream latency=%0d checked=%0d",
                 PIPELINE_LATENCY, checked_count);
        $finish;
    end
endmodule

`timescale 1ns/1ps

module tb_video_mode_1080p30;
    localparam integer H_TOTAL = 2200;
    localparam integer V_TOTAL = 1125;
    localparam integer H_ACTIVE = 1920;
    localparam integer V_ACTIVE = 1080;
    localparam integer FRAME_CYCLES = H_TOTAL * V_TOTAL;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    wire hs;
    wire vs;
    wire de;
    wire de_request;
    wire [11:0] x;
    wire [11:0] y;
    wire frame_start;

    integer errors = 0;
    integer active_count = 0;
    integer frame_start_count = 0;
    integer hs_count = 0;
    integer vs_count = 0;
    integer cycles_since_frame = 0;
    integer previous_frame_cycle = -1;
    integer cycle_count = 0;
    integer last_x = -1;
    integer last_y = -1;
    reg metrics_done = 1'b0;
    reg de_request_d1 = 1'b0;
    reg de_request_d2 = 1'b0;
    integer de_request_count = 0;

    always #5 clk = ~clk;

    video_mode_1080p30 dut (
        .clk(clk),
        .rst_n(rst_n),
        .hs(hs),
        .vs(vs),
        .de(de),
        .de_request(de_request),
        .x(x),
        .y(y),
        .frame_start(frame_start)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            de_request_d1 <= de_request;
            de_request_d2 <= de_request_d1;
            cycle_count = cycle_count + 1;
            if (frame_start) begin
                frame_start_count = frame_start_count + 1;
                if (frame_start_count == 1) begin
                    active_count = 0;
                    de_request_count = 0;
                    hs_count = 0;
                    vs_count = 0;
                    last_x = -1;
                    last_y = -1;
                end else if (frame_start_count == 2) begin
                    metrics_done = 1'b1;
                end
                if (previous_frame_cycle >= 0
                    && cycle_count - previous_frame_cycle != FRAME_CYCLES) begin
                    $display("FAIL: frame interval %0d, expected %0d",
                             cycle_count - previous_frame_cycle, FRAME_CYCLES);
                    errors = errors + 1;
                end
                previous_frame_cycle = cycle_count;
            end
            if (de && !metrics_done) begin
                active_count = active_count + 1;
                last_x = x;
                last_y = y;
                if (x >= H_ACTIVE || y >= V_ACTIVE) begin
                    $display("FAIL: active coordinate out of range (%0d,%0d)", x, y);
                    errors = errors + 1;
                end
            end
            if (de_request && !metrics_done)
                de_request_count = de_request_count + 1;
            if (cycle_count > 2 && de !== de_request_d2) begin
                $display("FAIL: de_request is not two clocks ahead of de");
                errors = errors + 1;
            end
            if (hs && !metrics_done)
                hs_count = hs_count + 1;
            if (vs && !metrics_done)
                vs_count = vs_count + 1;
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;

        // Two frame starts are needed to measure the exact 2200*1125 period.
        wait (metrics_done);

        if (frame_start_count != 2) begin
            $display("FAIL: expected two frame starts, got %0d", frame_start_count);
            errors = errors + 1;
        end
        if (active_count != H_ACTIVE * V_ACTIVE) begin
            $display("FAIL: expected %0d active pixels, got %0d",
                     H_ACTIVE * V_ACTIVE, active_count);
            errors = errors + 1;
        end
        if (de_request_count != H_ACTIVE * V_ACTIVE) begin
            $display("FAIL: expected %0d read-request pixels, got %0d",
                     H_ACTIVE * V_ACTIVE, de_request_count);
            errors = errors + 1;
        end
        if (last_x != H_ACTIVE - 1 || last_y != V_ACTIVE - 1) begin
            $display("FAIL: final active coordinate (%0d,%0d)", last_x, last_y);
            errors = errors + 1;
        end
        if (hs_count != 44 * V_TOTAL) begin
            $display("FAIL: expected %0d HS-high cycles, got %0d",
                     44 * V_TOTAL, hs_count);
            errors = errors + 1;
        end
        if (vs_count != 5 * H_TOTAL) begin
            $display("FAIL: expected %0d VS-high cycles, got %0d",
                     5 * H_TOTAL, vs_count);
            errors = errors + 1;
        end

        if (errors != 0)
            $fatal(1, "TEST_FAIL: video_mode_1080p30 errors=%0d", errors);

        $display("TEST_PASS: video_mode_1080p30");
        $finish;
    end
endmodule

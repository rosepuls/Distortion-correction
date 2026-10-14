`timescale 1ns/1ps

// One second of the current 30 fps capture / 60 Hz display architecture.
// Each input frame carries a unique RGB marker.  A late frame is allowed to
// repeat the last complete output, but a display marker may change only at a
// declared display boundary.
module tb_realtime_video_1s;
    localparam integer CORE_FRAME_CYCLES = 3_333_333;
    localparam integer HALF_DISPLAY_PERIOD = CORE_FRAME_CYCLES / 2;
    localparam integer INPUT_FRAME_COUNT = 30;
    localparam integer DISPLAY_REFRESH_COUNT = 60;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg input_frame_done = 1'b0;
    reg input_frame_bank = 1'b0;
    reg [23:0] input_frame_tag = 24'd0;
    reg display_frame_start = 1'b0;
    reg ddr_stall = 1'b0;

    wire capture_streaming;
    wire process_active;
    wire process_input_bank;
    wire process_output_bank;
    wire display_active;
    wire display_bank;
    wire display_tag_valid;
    wire [23:0] display_tag;
    wire input_overrun;
    wire ddr_stall_seen;
    wire [31:0] completed_frames;
    wire [31:0] display_refresh_count;

    integer cycle_count = 0;
    integer errors = 0;
    integer i;
    integer last_input_cycle = -1;
    integer next_input_cycle;
    integer observed_boundaries = 0;
    reg [23:0] previous_display_tag;
    reg previous_display_valid;
    reg display_boundary_seen;

    always #5 clk = ~clk;

    function automatic [23:0] frame_tag(input integer frame_index);
        begin
            frame_tag = 24'h102030 + (frame_index * 24'h010307);
        end
    endfunction

    task automatic check_cond(input condition, input [8*140-1:0] message);
        begin
            if (!condition) begin
                $display("FAIL: %0s", message);
                errors = errors + 1;
            end
        end
    endtask

    task automatic pulse_display_boundary(input integer expected_frame_index);
        begin
            @(negedge clk);
            display_boundary_seen = 1'b1;
            display_frame_start = 1'b1;
            @(posedge clk);
            #1;
            display_frame_start = 1'b0;
            display_boundary_seen = 1'b0;
            observed_boundaries = observed_boundaries + 1;
            check_cond(display_tag_valid && display_tag == frame_tag(expected_frame_index),
                       "display sequence or frame marker is incorrect");
        end
    endtask

    task automatic submit_input_frame(input integer frame_index);
        begin
            @(negedge clk);
            input_frame_bank = frame_index[0];
            input_frame_tag = frame_tag(frame_index);
            input_frame_done = 1'b1;
            @(negedge clk);
            input_frame_done = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        cycle_count = cycle_count + 1;
        if (rst_n && input_frame_done) begin
            if (last_input_cycle >= 0)
                check_cond(cycle_count - last_input_cycle == CORE_FRAME_CYCLES,
                           "input frames were not separated by the exact 30 fps interval");
            last_input_cycle = cycle_count;
        end
    end

    realtime_video_stream_harness #(
        .ALGORITHM_CYCLES(40),
        .OUTPUT_WRITE_CYCLES(24)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .input_frame_done(input_frame_done),
        .input_frame_bank(input_frame_bank), .input_frame_tag(input_frame_tag),
        .display_frame_start(display_frame_start), .ddr_stall(ddr_stall),
        .capture_streaming(capture_streaming),
        .process_active(process_active), .process_input_bank(process_input_bank),
        .process_output_bank(process_output_bank), .display_active(display_active),
        .display_bank(display_bank), .display_tag_valid(display_tag_valid),
        .display_tag(display_tag), .input_overrun(input_overrun),
        .ddr_stall_seen(ddr_stall_seen), .completed_frames(completed_frames),
        .display_refresh_count(display_refresh_count)
    );

    always @(display_tag or display_tag_valid) begin
        if (rst_n && previous_display_valid &&
            (display_tag != previous_display_tag || !display_tag_valid) &&
            !display_boundary_seen) begin
            $display("FAIL: display marker changed outside a frame boundary");
            errors = errors + 1;
        end
        previous_display_tag = display_tag;
        previous_display_valid = display_tag_valid;
    end

    initial begin
        previous_display_tag = 24'd0;
        previous_display_valid = 1'b0;
        display_boundary_seen = 1'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        submit_input_frame(0);
        next_input_cycle = cycle_count + CORE_FRAME_CYCLES;

        // Two 60 Hz refreshes are allocated to each 30 fps source frame.
        // Delay frame 1 across its first eligible refresh to verify safe
        // repetition of the prior complete frame.
        for (i = 1; i < INPUT_FRAME_COUNT; i = i + 1) begin
            if (i == 2) begin
                ddr_stall = 1'b1;
                while (cycle_count < next_input_cycle - HALF_DISPLAY_PERIOD - 2)
                    @(posedge clk);
                pulse_display_boundary(0);
                ddr_stall = 1'b0;
                while (cycle_count < next_input_cycle - 2) @(posedge clk);
                pulse_display_boundary(1);
            end else begin
                repeat (2) @(posedge clk);
                ddr_stall = 1'b1;
                repeat (3 + i) @(posedge clk);
                ddr_stall = 1'b0;
                while (cycle_count < next_input_cycle - HALF_DISPLAY_PERIOD - 2)
                    @(posedge clk);
                pulse_display_boundary(i - 1);
                while (cycle_count < next_input_cycle - 2) @(posedge clk);
                pulse_display_boundary(i - 1);
            end

            submit_input_frame(i);
            repeat (2) @(posedge clk);
            check_cond(capture_streaming && process_active && display_active,
                       "capture, processing and display were not concurrent");
            check_cond(process_output_bank != display_bank,
                       "processing selected the bank currently displayed");
            next_input_cycle = next_input_cycle + CORE_FRAME_CYCLES;
        end

        while (cycle_count < next_input_cycle - HALF_DISPLAY_PERIOD - 2)
            @(posedge clk);
        pulse_display_boundary(INPUT_FRAME_COUNT - 1);
        while (cycle_count < next_input_cycle - 1) @(posedge clk);
        pulse_display_boundary(INPUT_FRAME_COUNT - 1);

        check_cond(observed_boundaries == DISPLAY_REFRESH_COUNT,
                   "one-second run did not produce exactly 60 display refreshes");
        check_cond(display_refresh_count == DISPLAY_REFRESH_COUNT,
                   "harness display refresh counter disagrees with testbench");
        check_cond(completed_frames == INPUT_FRAME_COUNT,
                   "not every input frame reached a completed output bank");
        check_cond(!input_overrun, "scheduler raised input_overrun at 30 fps");
        check_cond(ddr_stall_seen, "DDR stall injection was not observed");

        if (errors != 0)
            $fatal(1, "TEST_FAIL: realtime_video_1s errors=%0d", errors);
        $display("TEST_PASS: realtime_video_1s input_frames=%0d display_refreshes=%0d",
                 INPUT_FRAME_COUNT, DISPLAY_REFRESH_COUNT);
        $finish;
    end
endmodule

`timescale 1ns/1ps

// Five 1280x720 frame tokens at a true 30 fps core-clock interval.  Each
// token represents a whole solid-colour video frame; the harness preserves
// that tag through capture, correction/write and display-bank selection.
module tb_realtime_video_stream;
    localparam integer CORE_FRAME_CYCLES = 3_333_333; // 100 MHz / 30 fps
    localparam integer FRAME_COUNT = 5;

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

    integer cycle_count = 0;
    integer errors = 0;
    integer i;
    integer last_input_cycle = -1;
    integer next_input_cycle;
    reg [23:0] expected_tags [0:FRAME_COUNT-1];
    reg [23:0] previous_display_tag;
    reg previous_display_valid;
    reg display_boundary_seen;
    reg display_changed;

    always #5 clk = ~clk;
    always @(posedge clk) begin
        cycle_count = cycle_count + 1;
        if (rst_n && input_frame_done) begin
            if (last_input_cycle >= 0)
                check_cond(cycle_count - last_input_cycle == CORE_FRAME_CYCLES,
                           "source frames were not separated by the exact 30 fps interval");
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
        .ddr_stall_seen(ddr_stall_seen), .completed_frames(completed_frames)
    );

    task automatic check_cond(input condition, input [8*120-1:0] message);
        begin
            if (!condition) begin
                $display("FAIL: %0s", message);
                errors = errors + 1;
            end
        end
    endtask

    task automatic pulse_display_boundary;
        begin
            @(negedge clk);
            display_boundary_seen = 1'b1;
            display_frame_start = 1'b1;
            @(posedge clk);
            #1;
            display_frame_start = 1'b0;
            display_boundary_seen = 1'b0;
        end
    endtask

    task automatic submit_input_frame(input integer frame_index);
        begin
            @(negedge clk);
            input_frame_bank = frame_index[0];
            input_frame_tag = expected_tags[frame_index];
            input_frame_done = 1'b1;
            @(negedge clk);
            input_frame_done = 1'b0;
        end
    endtask

    // An output tag may change only in a declared display frame boundary.
    always @(display_tag or display_tag_valid) begin
        if (rst_n && previous_display_valid &&
            (display_tag != previous_display_tag || !display_tag_valid) &&
            !display_boundary_seen) begin
            $display("FAIL: display tag changed outside a frame boundary");
            errors = errors + 1;
        end
        previous_display_tag = display_tag;
        previous_display_valid = display_tag_valid;
    end

    initial begin
        expected_tags[0] = 24'hE02020; // red
        expected_tags[1] = 24'h20D040; // green
        expected_tags[2] = 24'h3060E0; // blue
        expected_tags[3] = 24'hE0B020; // amber
        expected_tags[4] = 24'hC040D0; // magenta
        previous_display_tag = 24'd0;
        previous_display_valid = 1'b0;
        display_boundary_seen = 1'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // First capture begins at frame zero.  Every following source-frame
        // token is exactly one 30 fps period after its predecessor.
        submit_input_frame(0);
        next_input_cycle = cycle_count + CORE_FRAME_CYCLES;
        for (i = 1; i < FRAME_COUNT; i = i + 1) begin
            // Inject a different short DDR stall in each frame's processing
            // interval.  It must delay completion, never reorder/drop a tag.
            // The scheduler has issued the modelled DDR read by this point;
            // stall its active transaction rather than the later arithmetic.
            repeat (2) @(posedge clk);
            ddr_stall = 1'b1;
            repeat (3 + i) @(posedge clk);
            ddr_stall = 1'b0;
            while (cycle_count < next_input_cycle - 2) @(posedge clk);
            pulse_display_boundary();
            check_cond(display_tag_valid,
                       "a completed output was not available at the next display boundary");
            check_cond(display_tag == expected_tags[i-1],
                       "displayed frame tag is not the preceding captured frame");
            submit_input_frame(i);
            // Capturing the next frame, processing its predecessor and
            // displaying the prior output must overlap after frame one.
            repeat (2) @(posedge clk);
            check_cond(capture_streaming && process_active && display_active,
                       "capture, processing and display were not concurrent");
            check_cond(process_output_bank != display_bank,
                       "processing selected the bank currently displayed");
            next_input_cycle = next_input_cycle + CORE_FRAME_CYCLES;
        end

        // Adopt the fifth result on one final output-frame boundary.
        while (cycle_count < next_input_cycle - 1) @(posedge clk);
        pulse_display_boundary();
        check_cond(display_tag_valid && display_tag == expected_tags[FRAME_COUNT-1],
                   "final display tag did not match the fifth captured frame");
        check_cond(completed_frames == FRAME_COUNT,
                   "not every captured frame reached a completed output bank");
        check_cond(!input_overrun, "scheduler raised input_overrun at 30 fps");
        check_cond(ddr_stall_seen, "DDR stall injection was not observed");

        if (errors != 0)
            $fatal(1, "TEST_FAIL: realtime_video_stream errors=%0d", errors);
        $display("TEST_PASS: realtime_video_stream frames=%0d frame_period=%0d",
                 FRAME_COUNT, CORE_FRAME_CYCLES);
        $finish;
    end
endmodule

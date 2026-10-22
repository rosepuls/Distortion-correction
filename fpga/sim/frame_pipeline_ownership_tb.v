`timescale 1ns / 1ps

module frame_pipeline_ownership_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rstn = 1'b0;
    reg capture_begin = 1'b0;
    reg capture_publish = 1'b0;
    reg capture_abort = 1'b0;
    reg display_take = 1'b0;
    reg display_release = 1'b0;
    reg copy_start_ready = 1'b0;
    reg copy_done = 1'b0;
    reg copy_error = 1'b0;
    wire capture_begin_ready;
    wire [1:0] capture_begin_slot;
    wire capture_active;
    wire [1:0] capture_slot;
    wire display_take_ready;
    wire display_active;
    wire [1:0] display_slot;
    wire [31:0] display_sequence;
    wire copy_start;
    wire [1:0] copy_input_slot;
    wire [1:0] copy_output_slot;
    wire [31:0] copy_input_sequence;
    wire copy_active;
    wire [31:0] copied_count;
    wire [31:0] copy_error_count;
    wire [15:0] capture_dropped_ready_count;
    wire [15:0] output_dropped_ready_count;

    frame_pipeline_ownership dut (
        .clk(clk), .rstn(rstn),
        .capture_begin(capture_begin),
        .capture_begin_ready(capture_begin_ready),
        .capture_begin_slot(capture_begin_slot),
        .capture_active(capture_active),
        .capture_slot(capture_slot),
        .capture_publish(capture_publish),
        .capture_abort(capture_abort),
        .display_take(display_take),
        .display_take_ready(display_take_ready),
        .display_active(display_active),
        .display_slot(display_slot),
        .display_sequence(display_sequence),
        .display_release(display_release),
        .copy_start(copy_start),
        .copy_start_ready(copy_start_ready),
        .copy_input_slot(copy_input_slot),
        .copy_output_slot(copy_output_slot),
        .copy_input_sequence(copy_input_sequence),
        .copy_done(copy_done),
        .copy_error(copy_error),
        .copy_active(copy_active),
        .copied_count(copied_count),
        .copy_error_count(copy_error_count),
        .capture_dropped_ready_count(capture_dropped_ready_count),
        .output_dropped_ready_count(output_dropped_ready_count)
    );

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL at %0t: %0s", $time, message);
                $fatal(1);
            end
        end
    endtask

    task begin_capture;
        input [1:0] expected_slot;
        begin
            @(negedge clk);
            check(capture_begin_ready && capture_begin_slot == expected_slot,
                  "capture slot allocation");
            capture_begin = 1'b1;
            tick();
            check(capture_active && capture_slot == expected_slot,
                  "capture lease acquired");
            @(negedge clk);
            capture_begin = 1'b0;
        end
    endtask

    task publish_capture;
        begin
            capture_publish = 1'b1;
            tick();
            @(negedge clk);
            capture_publish = 1'b0;
        end
    endtask

    task finish_copy;
        input fail_copy;
        begin
            copy_start_ready = 1'b1;
            tick();
            check(copy_active && !copy_start, "copy engine start accepted");
            @(negedge clk);
            copy_start_ready = 1'b0;
            copy_done = !fail_copy;
            copy_error = fail_copy;
            tick();
            @(negedge clk);
            copy_done = 1'b0;
            copy_error = 1'b0;
        end
    endtask

    initial begin
        tick(); tick();
        @(negedge clk);
        rstn = 1'b1;

        begin_capture(2'd0);
        publish_capture();
        tick();
        check(copy_start && copy_active && copy_input_slot == 0 &&
              copy_output_slot == 0 && copy_input_sequence == 1,
              "first copy owns input 0 and output 0");
        tick();
        check(copy_start && copy_active, "copy start holds under backpressure");
        @(negedge clk);
        finish_copy(1'b0);
        check(copied_count == 1 && copy_error_count == 0 && display_take_ready,
              "first processed frame published");
        display_take = 1'b1;
        tick();
        check(display_active && display_slot == 0 && display_sequence == 1,
              "display holds first output frame");
        @(negedge clk);
        display_take = 1'b0;

        begin_capture(2'd0);
        publish_capture();
        tick();
        check(copy_start && copy_input_slot == 0 && copy_output_slot == 1,
              "new output slot does not overwrite display slot");
        @(negedge clk);
        finish_copy(1'b0);
        check(copied_count == 2 && display_slot == 0 && display_take_ready,
              "display lease survives later publish");
        display_take = 1'b1;
        tick();
        check(display_slot == 1 && display_sequence == 2,
              "display switches to second output frame");
        @(negedge clk);
        display_take = 1'b0;

        begin_capture(2'd0);
        publish_capture();
        tick();
        check(copy_start && copy_output_slot == 0, "released output slot reusable");
        @(negedge clk);
        finish_copy(1'b1);
        check(copy_error_count == 1 && copied_count == 2 && !display_take_ready,
              "failed copy aborts output without publishing");
        check(display_active && display_slot == 1 && display_sequence == 2,
              "failed copy leaves display frame intact");

        // The copy engine is slower than capture. Protect its READING slot,
        // drop the older waiting input frame, and process the newest one next.
        begin_capture(2'd0);
        publish_capture();
        tick();
        check(copy_start && copy_input_slot == 0 && copy_output_slot == 0,
              "slow copy leases input 0 and output 0");
        begin_capture(2'd1);
        publish_capture();
        begin_capture(2'd2);
        publish_capture();
        check(capture_dropped_ready_count == 1,
              "older waiting capture frame was dropped");
        check(copy_start && copy_input_slot == 0 && copy_input_sequence == 4,
              "active copy input remains protected");
        finish_copy(1'b0);
        tick();
        check(copy_start && copy_input_slot == 2 && copy_input_sequence == 6,
              "next copy takes newest capture frame");
        check(copy_output_slot == 2 && display_slot == 1,
              "output writer avoids display and READY slots");
        @(negedge clk);
        finish_copy(1'b0);
        check(output_dropped_ready_count == 1,
              "older undisplayed output frame was dropped");
        check(display_slot == 1 && display_sequence == 2,
              "display still owns the previous frame");
        display_take = 1'b1;
        tick();
        check(display_slot == 2 && display_sequence == 4,
              "display takes newest processed frame");
        @(negedge clk);
        display_take = 1'b0;

        $display("PASS: frame_pipeline_ownership two-pool handoff test");
        $finish;
    end
endmodule

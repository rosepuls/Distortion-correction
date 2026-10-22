`timescale 1ns / 1ps

module capture_frame_admission_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rstn = 1'b0;
    reg frame_end = 1'b0;
    reg frame_complete = 1'b0;
    reg write_idle = 1'b0;
    wire capture_begin;
    wire capture_publish;
    wire capture_abort;
    wire allow_capture;
    wire [15:0] drain_wait_cycles;
    wire begin_ready;
    wire producer_active;
    wire [1:0] producer_slot;
    wire [31:0] publish_sequence;
    wire [15:0] producer_abort_count;

    capture_frame_admission dut (
        .clk(clk), .rstn(rstn),
        .frame_end(frame_end), .frame_complete(frame_complete),
        .write_idle(write_idle),
        .capture_begin_ready(begin_ready),
        .capture_begin(capture_begin),
        .capture_publish(capture_publish),
        .capture_abort(capture_abort),
        .allow_capture(allow_capture),
        .drain_wait_cycles(drain_wait_cycles)
    );

    frame_pool_manager pool (
        .clk(clk), .rstn(rstn),
        .producer_begin(capture_begin),
        .producer_begin_ready(begin_ready),
        .producer_begin_slot(),
        .producer_active(producer_active),
        .producer_slot(producer_slot),
        .producer_publish(capture_publish),
        .producer_abort(capture_abort),
        .consumer_take(1'b0),
        .consumer_release(1'b0),
        .publish_sequence(publish_sequence),
        .producer_abort_count(producer_abort_count)
    );

    task tick;
        begin @(posedge clk); #1; end
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

    initial begin
        tick(); tick();
        @(negedge clk);
        rstn = 1'b1;
        tick();
        check(producer_active && producer_slot == 0 && allow_capture,
              "initial frame admitted into first slot");

        @(negedge clk);
        frame_end = 1'b1;
        frame_complete = 1'b1;
        write_idle = 1'b1;
        #1;
        check(!capture_publish && !capture_abort && !allow_capture,
              "VS closes admission before write pipeline settles");
        tick();
        @(negedge clk);
        frame_end = 1'b0;
        repeat (8) tick();
        check(capture_publish && !capture_abort,
              "complete drained frame publishes after settling");
        tick();
        check(publish_sequence == 1 && !producer_active,
              "first frame is READY after publish");
        @(negedge clk);
        frame_complete = 1'b0;
        tick();
        check(producer_active && producer_slot == 1 && allow_capture,
              "next frame receives a different slot");

        @(negedge clk);
        frame_end = 1'b1;
        write_idle = 1'b0;
        #1;
        check(!capture_publish && !capture_abort && !allow_capture,
              "incomplete frame closes admission immediately");
        tick();
        @(negedge clk);
        frame_end = 1'b0;
        repeat (3) begin
            tick();
            check(producer_active && producer_slot == 1 && !allow_capture &&
                  !capture_begin && !capture_abort,
                  "old slot retained while writes remain outstanding");
        end
        check(drain_wait_cycles >= 3, "write-drain wait diagnosed");

        @(negedge clk);
        write_idle = 1'b1;
        repeat (5) tick();
        #1;
        check(capture_abort && !capture_begin, "abort only after write drain");
        tick();
        check(producer_abort_count == 1 && publish_sequence == 1 &&
              !producer_active, "incomplete frame never published");
        @(negedge clk);
        tick();
        check(producer_active && producer_slot == 1 && allow_capture,
              "aborted slot can be reused after drain");

        @(negedge clk);
        frame_end = 1'b1;
        frame_complete = 1'b1;
        write_idle = 1'b0;
        tick();
        @(negedge clk);
        frame_end = 1'b0;
        repeat (2) begin
            tick();
            check(producer_active && !allow_capture && !capture_abort,
                  "complete frame waits for pending writes");
        end
        @(negedge clk);
        write_idle = 1'b1;
        repeat (6) tick();
        #1;
        check(capture_publish && !capture_abort,
              "complete frame publishes after write drain");
        tick();
        check(publish_sequence == 2 && !producer_active,
              "drained complete frame becomes READY");

        $display("PASS: capture_frame_admission publish and drain test");
        $finish;
    end
endmodule

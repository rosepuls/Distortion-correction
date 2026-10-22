`timescale 1ns / 1ps

module frame_pool_manager_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rstn = 1'b0;
    reg producer_begin = 1'b0;
    reg producer_publish = 1'b0;
    reg producer_abort = 1'b0;
    reg consumer_take = 1'b0;
    reg consumer_release = 1'b0;
    wire producer_begin_ready;
    wire [1:0] producer_begin_slot;
    wire producer_active;
    wire [1:0] producer_slot;
    wire consumer_take_ready;
    wire [1:0] consumer_take_slot;
    wire [31:0] consumer_take_sequence;
    wire consumer_active;
    wire [1:0] consumer_slot;
    wire [31:0] consumer_sequence;
    wire ready_valid;
    wire [1:0] ready_slot;
    wire [31:0] ready_sequence;
    wire [31:0] publish_sequence;
    wire [15:0] producer_busy_count;
    wire [15:0] producer_no_slot_count;
    wire [15:0] producer_abort_count;
    wire [15:0] dropped_ready_count;
    wire [15:0] consumer_empty_count;
    wire [15:0] producer_protocol_error_count;
    wire [15:0] consumer_protocol_error_count;

    frame_pool_manager dut (
        .clk(clk), .rstn(rstn),
        .producer_begin(producer_begin),
        .producer_begin_ready(producer_begin_ready),
        .producer_begin_slot(producer_begin_slot),
        .producer_active(producer_active),
        .producer_slot(producer_slot),
        .producer_publish(producer_publish),
        .producer_abort(producer_abort),
        .consumer_take(consumer_take),
        .consumer_take_ready(consumer_take_ready),
        .consumer_take_slot(consumer_take_slot),
        .consumer_take_sequence(consumer_take_sequence),
        .consumer_active(consumer_active),
        .consumer_slot(consumer_slot),
        .consumer_sequence(consumer_sequence),
        .consumer_release(consumer_release),
        .ready_valid(ready_valid),
        .ready_slot(ready_slot),
        .ready_sequence(ready_sequence),
        .publish_sequence(publish_sequence),
        .producer_busy_count(producer_busy_count),
        .producer_no_slot_count(producer_no_slot_count),
        .producer_abort_count(producer_abort_count),
        .dropped_ready_count(dropped_ready_count),
        .consumer_empty_count(consumer_empty_count),
        .producer_protocol_error_count(producer_protocol_error_count),
        .consumer_protocol_error_count(consumer_protocol_error_count)
    );

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task check;
        input condition;
        input [8*96-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL at %0t: %0s", $time, message);
                $fatal(1);
            end
        end
    endtask

    initial begin
        tick();
        tick();
        @(negedge clk);
        rstn = 1'b1;

        // First complete frame can be leased; the producer then uses a
        // different slot while the consumer holds the old one.
        check(producer_begin_ready && producer_begin_slot == 0, "first free slot");
        producer_begin = 1'b1;
        tick();
        check(producer_active && producer_slot == 0, "producer owns slot 0");
        @(negedge clk);
        producer_begin = 1'b0;
        producer_publish = 1'b1;
        tick();
        check(ready_valid && ready_slot == 0 && ready_sequence == 1, "first frame ready");
        @(negedge clk);
        producer_publish = 1'b0;
        consumer_take = 1'b1;
        tick();
        check(consumer_active && consumer_slot == 0 && consumer_sequence == 1,
              "consumer takes first frame");
        @(negedge clk);
        consumer_take = 1'b0;
        check(producer_begin_slot == 1, "reading slot stays protected");
        producer_begin = 1'b1;
        tick();
        @(negedge clk);
        producer_begin = 1'b0;
        producer_publish = 1'b1;
        tick();
        check(ready_valid && ready_slot == 1 && ready_sequence == 2, "second frame ready");
        @(negedge clk);
        producer_publish = 1'b0;
        consumer_take = 1'b1;
        tick();
        check(consumer_slot == 1 && consumer_sequence == 2, "take switches lease");
        @(negedge clk);
        consumer_take = 1'b0;
        check(producer_begin_slot == 0, "previous lease is free");

        // Publish two frames without a display take. The older READY slot
        // must be reclaimed, never the slot currently being read.
        producer_begin = 1'b1;
        tick();
        @(negedge clk);
        producer_begin = 1'b0;
        producer_publish = 1'b1;
        tick();
        @(negedge clk);
        producer_publish = 1'b0;
        check(ready_slot == 0 && ready_sequence == 3, "third frame ready");
        check(producer_begin_slot == 2, "only free slot is 2");
        producer_begin = 1'b1;
        tick();
        @(negedge clk);
        producer_begin = 1'b0;
        producer_publish = 1'b1;
        tick();
        check(ready_slot == 2 && ready_sequence == 4, "newest READY retained");
        check(dropped_ready_count == 1, "old READY counted as dropped");
        check(consumer_slot == 1, "active reader was not overwritten");
        @(negedge clk);
        producer_publish = 1'b0;
        consumer_take = 1'b1;
        tick();
        check(consumer_slot == 2 && consumer_sequence == 4, "take newest frame");
        @(negedge clk);
        tick();
        check(consumer_slot == 2 && consumer_sequence == 4,
              "empty take keeps current lease");
        check(consumer_empty_count == 1, "empty take diagnosed");
        @(negedge clk);
        consumer_take = 1'b0;

        // An incomplete frame is returned to FREE without publishing.
        check(producer_begin_slot == 0, "evicted READY slot reusable");
        producer_begin = 1'b1;
        tick();
        @(negedge clk);
        producer_begin = 1'b0;
        producer_abort = 1'b1;
        tick();
        check(producer_abort_count == 1 && publish_sequence == 4,
              "abort did not publish");
        @(negedge clk);
        producer_abort = 1'b0;
        consumer_release = 1'b1;
        tick();
        check(!consumer_active && producer_begin_ready, "release frees lease");
        @(negedge clk);
        consumer_release = 1'b0;
        check(producer_protocol_error_count == 0 && consumer_protocol_error_count == 0,
              "no protocol errors");

        // A READY frame taken on the same edge as a new publish must retain
        // its lease; the newly published frame remains READY for a later take.
        producer_begin = 1'b1;
        tick();
        @(negedge clk);
        producer_begin = 1'b0;
        producer_publish = 1'b1;
        tick();
        check(ready_slot == 0 && ready_sequence == 5, "fifth frame ready");
        @(negedge clk);
        producer_publish = 1'b0;
        producer_begin = 1'b1;
        tick();
        check(producer_slot == 1, "next producer slot distinct from READY");
        @(negedge clk);
        producer_begin = 1'b0;
        producer_publish = 1'b1;
        consumer_take = 1'b1;
        tick();
        check(consumer_active && consumer_slot == 0 && consumer_sequence == 5,
              "simultaneous take protects old READY frame");
        check(ready_valid && ready_slot == 1 && ready_sequence == 6,
              "simultaneous publish exposes new frame");
        check(dropped_ready_count == 1, "taken frame is not dropped");
        @(negedge clk);
        producer_publish = 1'b0;
        tick();
        check(consumer_slot == 1 && consumer_sequence == 6,
              "consumer switches to frame published on previous edge");
        @(negedge clk);
        consumer_take = 1'b0;
        consumer_release = 1'b1;
        tick();
        check(!consumer_active, "final release");
        check(producer_protocol_error_count == 0 && consumer_protocol_error_count == 0,
              "concurrent handshake has no protocol errors");
        $display("PASS: frame_pool_manager directed ownership test");
        $finish;
    end
endmodule

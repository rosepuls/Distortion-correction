`timescale 1ns / 1ps

module ddr_write_drain_tracker_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rstn = 1'b0;
    reg awvalid = 1'b0;
    reg awready = 1'b0;
    reg [3:0] awid = 4'd0;
    reg wready = 1'b0;
    reg wusero_last = 1'b0;
    reg [3:0] wusero_id = 4'd0;
    reg capture_source_busy = 1'b0;
    reg copy_source_busy = 1'b0;
    wire capture_write_idle;
    wire copy_write_idle;
    wire [15:0] capture_outstanding;
    wire [15:0] copy_outstanding;
    wire [15:0] protocol_error_count;
    wire protocol_fault;

    ddr_write_drain_tracker dut (
        .clk(clk), .rstn(rstn),
        .awvalid(awvalid), .awready(awready), .awid(awid),
        .wready(wready), .wusero_last(wusero_last), .wusero_id(wusero_id),
        .capture_source_busy(capture_source_busy),
        .copy_source_busy(copy_source_busy),
        .capture_write_idle(capture_write_idle),
        .copy_write_idle(copy_write_idle),
        .capture_outstanding(capture_outstanding),
        .copy_outstanding(copy_outstanding),
        .protocol_error_count(protocol_error_count),
        .protocol_fault(protocol_fault)
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
        #1;
        check(capture_write_idle && copy_write_idle, "both sources idle after reset");

        capture_source_busy = 1'b1;
        #1;
        check(!capture_write_idle && copy_write_idle, "pending capture request blocks only capture");
        capture_source_busy = 1'b0;
        awvalid = 1'b1;
        awid = 4'd0;
        #1;
        check(!capture_write_idle, "unaccepted AW blocks idle");
        tick();
        check(capture_outstanding == 0, "AW waits for ready");

        @(negedge clk);
        awready = 1'b1;
        tick();
        check(capture_outstanding == 1, "capture AW accepted");
        @(negedge clk);
        awid = 4'd1;
        tick();
        check(copy_outstanding == 1 && !copy_write_idle,
              "copy write tracked independently");

        @(negedge clk);
        awvalid = 1'b0;
        wusero_last = 1'b1;
        wusero_id = 4'd0;
        wready = 1'b0;
        tick();
        check(capture_outstanding == 1 && !capture_write_idle,
              "last without a valid write-data beat must not drain capture");
        @(negedge clk);
        wready = 1'b1;
        #1;
        check(!capture_write_idle, "valid completion edge is still busy");
        tick();
        check(capture_outstanding == 0 && copy_outstanding == 1,
              "capture completion does not release copy");
        @(negedge clk);
        wusero_last = 1'b0;
        wready = 1'b0;
        #1;
        check(capture_write_idle && !copy_write_idle,
              "capture drained while copy remains busy");

        awvalid = 1'b1;
        awid = 4'd1;
        wusero_last = 1'b1;
        wusero_id = 4'd1;
        wready = 1'b1;
        tick();
        check(copy_outstanding == 1 && !protocol_fault,
              "simultaneous copy accept and completion preserve count");
        @(negedge clk);
        awvalid = 1'b0;
        wready = 1'b0;
        tick();
        check(copy_outstanding == 1 && !protocol_fault,
              "held completion level is counted only once");
        @(negedge clk);
        wusero_last = 1'b0;
        wready = 1'b0;
        tick();
        @(negedge clk);
        wusero_last = 1'b1;
        wready = 1'b1;
        tick();
        check(copy_outstanding == 0 && !protocol_fault,
              "copy drains after distinct completion pulse");
        @(negedge clk);
        wusero_last = 1'b0;
        wready = 1'b0;
        #1;
        check(copy_write_idle, "copy idle after return signal clears");

        wusero_last = 1'b1;
        wready = 1'b1;
        wusero_id = 4'd0;
        tick();
        check(protocol_fault && protocol_error_count == 1 &&
              !capture_write_idle && !copy_write_idle,
              "orphan completion latches fault and prevents unsafe publish");
        $display("PASS: ddr_write_drain_tracker ownership and fault test");
        $finish;
    end
endmodule

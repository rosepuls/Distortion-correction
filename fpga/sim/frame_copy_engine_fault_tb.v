`timescale 1ns / 1ps

module frame_copy_engine_fault_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0, start = 0, read_rvalid = 0, read_rlast = 0;
    wire start_ready, read_valid, write_awvalid, copy_done, copy_error;
    wire fatal_fault;
    frame_copy_engine #(.BURSTS_PER_FRAME(2), .STALL_LIMIT(100)) dut (
        .clk(clk), .rstn(rstn), .start(start), .start_ready(start_ready),
        .input_slot(2'd0), .output_slot(2'd0), .input_sequence(32'd7),
        .copy_done(copy_done), .copy_error(copy_error), .active(),
        .fatal_fault(fatal_fault), .completed_sequence(),
        .read_valid(read_valid), .read_addr(), .read_len(),
        .read_reserve(), .read_ready(1'b1),
        .read_rvalid(read_rvalid), .read_rdata(256'h1234),
        .read_rlast(read_rlast),
        .write_awvalid(write_awvalid), .write_awaddr(), .write_awlen(),
        .write_awready(1'b1), .write_wvalid(), .write_wdata(),
        .write_wstrb(), .write_wready(1'b0), .write_wlast(1'b0),
        .write_source_busy(), .copy_write_idle(1'b1),
        .read_fault(1'b0), .write_fault(1'b0)
    );
    always @(posedge clk) if (rstn && (write_awvalid || copy_done)) begin
        $display("FAIL: partial read reached output publication"); $fatal(1);
    end
    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk); rstn = 1; start = 1;
        @(posedge clk); #1; start = 0;
        wait (read_valid);
        @(posedge clk); #1;
        @(negedge clk); read_rvalid = 1; read_rlast = 1;
        @(posedge clk); #1;
        read_rvalid = 0; read_rlast = 0;
        wait (copy_error);
        #1;
        if (!fatal_fault || start_ready) begin
            $display("FAIL: malformed RLAST did not lock copy engine"); $fatal(1);
        end
        $display("PASS: frame_copy_engine short read aborts without publishing");
        $finish;
    end
    initial begin
        repeat (100) @(posedge clk);
        $display("FAIL: copy fault timeout"); $fatal(1);
    end
endmodule

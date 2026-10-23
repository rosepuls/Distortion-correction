`timescale 1ns / 1ps

module ddr_read_burst_arbiter_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rstn = 1'b0;
    reg c0_valid = 1'b0, c1_valid = 1'b0;
    reg c0_reserve = 1'b0, c1_reserve = 1'b0;
    reg [27:0] c0_addr = 28'd0, c1_addr = 28'd0;
    reg [3:0] c0_len = 4'd0, c1_len = 4'd0;
    wire c0_ready, c1_ready;
    wire c0_rvalid, c1_rvalid, c0_rlast, c1_rlast;
    wire [255:0] c0_rdata, c1_rdata;
    wire [27:0] axi_araddr;
    wire [3:0] axi_arid;
    wire [3:0] axi_arlen;
    wire axi_arvalid;
    reg axi_arready = 1'b1;
    reg [255:0] axi_rdata = 256'd0;
    reg axi_rvalid = 1'b0, axi_rlast = 1'b0;
    reg [3:0] axi_rid = 4'd0;
    wire busy;
    wire c1_wait_arbiter, c1_wait_arready;
    wire [15:0] response_error_count;

    ddr_read_burst_arbiter dut (
        .clk(clk), .rstn(rstn),
        .c0_valid(c0_valid), .c0_addr(c0_addr), .c0_len(c0_len),
        .c0_reserve(c0_reserve), .c0_ready(c0_ready),
        .c0_rvalid(c0_rvalid), .c0_rdata(c0_rdata), .c0_rlast(c0_rlast),
        .c1_valid(c1_valid), .c1_addr(c1_addr), .c1_len(c1_len),
        .c1_reserve(c1_reserve), .c1_ready(c1_ready),
        .c1_rvalid(c1_rvalid), .c1_rdata(c1_rdata), .c1_rlast(c1_rlast),
        .axi_araddr(axi_araddr), .axi_arid(axi_arid), .axi_arlen(axi_arlen),
        .axi_arvalid(axi_arvalid), .axi_arready(axi_arready),
        .axi_rdata(axi_rdata), .axi_rvalid(axi_rvalid), .axi_rlast(axi_rlast),
        .axi_rid(axi_rid),
        .busy(busy), .response_error_count(response_error_count),
        .c1_wait_arbiter(c1_wait_arbiter),
        .c1_wait_arready(c1_wait_arready)
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
        c0_valid = 1'b1; c0_addr = 28'h0001000; c0_len = 4'd0;
        c1_valid = 1'b1; c1_addr = 28'h0c01000; c1_len = 4'd1;
        c0_reserve = 1'b0; c1_reserve = 1'b1;
        #1;
        check(axi_arvalid && axi_araddr == c1_addr && axi_arlen == 1 &&
              c1_ready && !c0_ready, "unreserved client cannot issue");
        tick();
        check(busy, "accepted burst owns read return path");
        check(c1_wait_arbiter && !c1_wait_arready,
              "client 1 arbitration wait is counted while another burst is active");
        @(negedge clk);
        c1_valid = 1'b0; c0_reserve = 1'b1;
        axi_rid = 4'd1;
        #1;
        check(!axi_arvalid && !c0_ready, "second burst waits for response");
        axi_rvalid = 1'b1; axi_rdata = 256'h11; axi_rlast = 1'b0;
        #1;
        check(c1_rvalid && !c0_rvalid && c1_rdata[31:0] == 32'h11 &&
              !c1_rlast, "first beat routed to client 1");
        tick();
        @(negedge clk);
        axi_rdata = 256'h22; axi_rlast = 1'b1;
        #1;
        check(c1_rvalid && c1_rlast && !c0_rvalid,
              "last beat routed to client 1");
        tick();
        check(!busy, "read owner released on RLAST");
        @(negedge clk);
        axi_rvalid = 1'b0; axi_rlast = 1'b0;
        axi_rid = 4'd0;
        #1;
        check(axi_arvalid && axi_araddr == c0_addr && c0_ready,
              "waiting client 0 accepted after drain");
        tick();
        @(negedge clk);
        c0_valid = 1'b0;
        axi_rvalid = 1'b1; axi_rlast = 1'b1; axi_rdata = 256'h33;
        #1;
        check(c0_rvalid && c0_rlast && !c1_rvalid && c0_rdata[31:0] == 32'h33,
              "client 0 response routed correctly");
        tick();
        @(negedge clk);
        axi_rvalid = 1'b1; axi_rlast = 1'b1;
        #1;
        check(!c0_rvalid && !c1_rvalid, "orphan response not forwarded");
        tick();
        check(response_error_count == 1, "orphan response counted");
        @(negedge clk);
        axi_rvalid = 1'b0; axi_rlast = 1'b0;
        c0_valid = 1'b1; c0_len = 4'd1;
        tick();
        @(negedge clk);
        c0_valid = 1'b0;
        axi_rvalid = 1'b1; axi_rlast = 1'b1;
        tick();
        check(response_error_count == 2 && !busy,
              "premature RLAST counted and arbiter recovered");
        @(negedge clk);
        axi_rvalid = 1'b0; axi_rlast = 1'b0;
        c0_valid = 1'b1; c0_reserve = 1'b0;
        #1;
        check(!axi_arvalid && !c0_ready, "reservation gates every new burst");
        // A zero-latency single-beat response is routed using the grant of
        // this cycle, before the registered owner is available.
        c0_len = 4'd0;
        c0_reserve = 1'b1;
        axi_rvalid = 1'b1;
        axi_rlast = 1'b1;
        axi_rdata = 256'h44;
        #1;
        check(c0_ready && c0_rvalid && c0_rlast && c0_rdata[31:0] == 32'h44,
              "same-cycle AR and R response routed to grant owner");
        tick();
        check(!busy && response_error_count == 2,
              "same-cycle response closes burst without an error");
        @(negedge clk);
        c0_valid = 1'b0; axi_rvalid = 1'b0; axi_rlast = 1'b0;
        axi_arready = 1'b0;
        c0_valid = 1'b1; c0_addr = 28'h0002000; c0_len = 4'd3;
        c1_valid = 1'b0;
        #1;
        check(axi_arvalid && axi_araddr == 28'h0002000,
              "first stalled address selected");
        check(!c1_wait_arbiter && !c1_wait_arready,
              "client 1 not counted before it has a request");
        tick();
        @(negedge clk);
        c1_valid = 1'b1; c1_reserve = 1'b1;
        c1_addr = 28'h0c02000; c1_len = 4'd7;
        #1;
        check(axi_arvalid && axi_araddr == 28'h0002000 &&
              axi_arlen == 4'd3,
              "stalled AR address and length remain stable when competitor arrives");
        check(c1_wait_arbiter && !c1_wait_arready,
              "client 1 arbitration wait is distinct from DDR ARREADY wait");
        axi_arready = 1'b1;
        #1;
        check(c0_ready && !c1_ready,
              "stalled owner receives AR handshake");
        tick();
        @(negedge clk);
        c0_valid = 1'b0; c1_valid = 1'b0; axi_arready = 1'b0;
        axi_rvalid = 1'b1; axi_rlast = 1'b0; axi_rid = 4'd1;
        #1;
        check(!c0_rvalid && !c1_rvalid,
              "wrong RID is withheld from both clients");
        tick();
        check(response_error_count == 3,
              "wrong RID increments protocol error count");
        @(negedge clk);
        axi_rid = 4'd0; axi_rvalid = 1'b1; axi_rlast = 1'b1;
        tick();
        @(negedge clk);
        axi_rvalid = 1'b0; axi_rlast = 1'b0;
        c0_valid = 1'b0; c1_valid = 1'b1; c1_reserve = 1'b1;
        c1_addr = 28'h0c03000; c1_len = 4'd3; axi_arready = 1'b0;
        #1;
        check(axi_arvalid && c1_wait_arready && !c1_wait_arbiter,
              "selected client 1 distinguishes DDR ARREADY backpressure");
        $display("PASS: ddr_read_burst_arbiter reservation and routing test");
        $finish;
    end
endmodule

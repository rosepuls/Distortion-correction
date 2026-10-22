`timescale 1ns / 1ps

module ddr_write_burst_arbiter_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg c0_awvalid = 0, c1_awvalid = 0;
    reg [27:0] c0_awaddr = 0, c1_awaddr = 0;
    reg [3:0] c0_awlen = 0, c1_awlen = 0;
    wire c0_awready, c1_awready, c0_wready, c1_wready;
    wire c0_wlast, c1_wlast;
    wire [27:0] axi_awaddr;
    wire [3:0] axi_awid, axi_awlen;
    wire axi_awvalid, axi_wvalid;
    wire [255:0] axi_wdata;
    wire [31:0] axi_wstrb;
    reg axi_awready = 0, axi_wready = 0, axi_wlast = 0;
    reg [3:0] axi_wusero_id = 0;
    wire busy;
    wire [15:0] protocol_error_count;
    wire protocol_fault;

    ddr_write_burst_arbiter dut (
        .clk(clk), .rstn(rstn),
        .c0_awvalid(c0_awvalid), .c0_awaddr(c0_awaddr), .c0_awlen(c0_awlen),
        .c0_awready(c0_awready), .c0_wvalid(c0_wready),
        .c0_wdata({8{32'hc0c0c0c0}}), .c0_wstrb(32'hffffffff),
        .c0_wready(c0_wready),
        .c0_wlast(c0_wlast),
        .c1_awvalid(c1_awvalid), .c1_awaddr(c1_awaddr), .c1_awlen(c1_awlen),
        .c1_awready(c1_awready), .c1_wvalid(1'b1),
        .c1_wdata({8{32'hc1c1c1c1}}), .c1_wstrb(32'hffffffff),
        .c1_wready(c1_wready),
        .c1_wlast(c1_wlast),
        .axi_awaddr(axi_awaddr), .axi_awid(axi_awid),
        .axi_awlen(axi_awlen), .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready),
        .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb),
        .axi_wvalid(axi_wvalid), .axi_wready(axi_wready),
        .axi_wlast(axi_wlast), .axi_wusero_id(axi_wusero_id),
        .busy(busy), .protocol_error_count(protocol_error_count),
        .protocol_fault(protocol_fault)
    );

    task check(input condition, input [8*100-1:0] description);
        begin
            if (condition !== 1'b1) begin
                $display("FAIL: %0s at %0t", description, $time);
                $fatal(1);
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        rstn = 1;
        c0_awvalid = 1; c0_awaddr = 28'h0001000; c0_awlen = 4'd1;
        #1;
        check(axi_awvalid && axi_awaddr == c0_awaddr && axi_awid == 0,
              "capture AW selected");
        @(posedge clk); #1;
        @(negedge clk);
        c1_awvalid = 1; c1_awaddr = 28'h0c01000; c1_awlen = 4'd0;
        #1;
        check(axi_awaddr == 28'h0001000 && axi_awlen == 4'd1 && axi_awid == 0,
              "stalled AW stays with capture after copy arrives");
        axi_awready = 1;
        #1;
        check(c0_awready && !c1_awready, "only capture AW accepted");
        @(posedge clk); #1;
        c0_awvalid = 0; axi_awready = 0;
        check(busy && !axi_awvalid, "AW owner retained into data phase");
        @(negedge clk);
        axi_wready = 1; axi_wlast = 0; axi_wusero_id = 0;
        #1;
        check(c0_wready && !c1_wready && axi_wvalid &&
              axi_wdata[31:0] == 32'hc0c0c0c0, "first capture beat selected");
        @(posedge clk); #1;
        @(negedge clk);
        axi_wlast = 1;
        #1;
        check(c0_wready && !c1_wready && c0_wlast && !c1_wlast,
              "capture owns last beat");
        @(posedge clk); #1;
        check(!busy, "last beat released owner");
        @(negedge clk);
        axi_wready = 0; axi_wlast = 0; axi_awready = 1;
        #1;
        check(axi_awvalid && axi_awaddr == 28'h0c01000 && axi_awid == 1,
              "waiting copy AW selected");
        @(posedge clk); #1;
        c1_awvalid = 0; axi_awready = 0;
        @(negedge clk);
        axi_wready = 1; axi_wlast = 1; axi_wusero_id = 1;
        #1;
        check(!c0_wready && c1_wready && !c0_wlast && c1_wlast && axi_wvalid &&
              axi_wdata[31:0] == 32'hc1c1c1c1, "copy data selected");
        @(posedge clk); #1;
        check(!busy && protocol_error_count == 0, "two bursts completed cleanly");

        // An ID mismatch on the Pango completion beat must be sticky.
        @(negedge clk);
        axi_wready = 0; axi_wlast = 0;
        c0_awvalid = 1; c0_awlen = 0; axi_awready = 1;
        @(posedge clk); #1;
        c0_awvalid = 0; axi_awready = 0;
        @(negedge clk);
        axi_wready = 1; axi_wlast = 1; axi_wusero_id = 1;
        @(posedge clk); #1;
        check(protocol_fault && protocol_error_count == 1,
              "mismatched completion ID recorded");
        $display("PASS: ddr_write_burst_arbiter owner, hold, and ID fault test");
        $finish;
    end

    initial begin
        repeat (1000) @(posedge clk);
        $display("FAIL: write arbiter timeout"); $fatal(1);
    end
endmodule

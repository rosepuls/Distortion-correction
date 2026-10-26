`timescale 1ns / 1ps

module stage7_read_arbiter_tb;
    reg clk = 1'b0;
    always #4 clk = ~clk;
    reg rstn = 1'b0;
    reg c0_valid = 1'b0, c1_valid = 1'b0;
    reg [27:0] c1_addr = 28'd0;
    wire c0_ready, c1_ready, c0_rvalid, c1_rvalid, c0_rlast, c1_rlast;
    wire [255:0] c0_rdata, c1_rdata;
    wire [27:0] axi_araddr;
    wire [3:0] axi_arid, axi_arlen;
    wire axi_arvalid;
    reg axi_rvalid = 1'b0, axi_rlast = 1'b0;
    reg [3:0] axi_rid = 4'd0;
    wire busy;
    wire [15:0] response_error_count;
    integer ar1_count = 0, ar0_count = 0;
    integer beat;

    ddr_read_burst_arbiter dut (
        .clk(clk), .rstn(rstn),
        .c0_valid(c0_valid), .c0_addr(28'h100000), .c0_len(4'd15),
        .c0_reserve(c0_valid), .c0_ready(c0_ready),
        .c0_rvalid(c0_rvalid), .c0_rdata(c0_rdata), .c0_rlast(c0_rlast),
        .c1_valid(c1_valid), .c1_addr(c1_addr), .c1_len(4'd3),
        .c1_reserve(c1_valid), .c1_ready(c1_ready),
        .c1_rvalid(c1_rvalid), .c1_rdata(c1_rdata), .c1_rlast(c1_rlast),
        .axi_araddr(axi_araddr), .axi_arid(axi_arid),
        .axi_arlen(axi_arlen), .axi_arvalid(axi_arvalid),
        .axi_arready(1'b1), .axi_rdata(256'h55),
        .axi_rvalid(axi_rvalid), .axi_rlast(axi_rlast),
        .axi_rid(axi_rid), .busy(busy),
        .response_error_count(response_error_count),
        .c1_wait_arbiter(), .c1_wait_arready()
    );

    always @(posedge clk) if (rstn && axi_arvalid) begin
        if (axi_arid == 4'd1) begin
            if (!c1_ready || axi_araddr !== ar1_count * 1280 || axi_arlen !== 4'd3)
                $fatal(1, "Transform AR mismatch");
            ar1_count <= ar1_count + 1;
        end else if (axi_arid == 4'd0) begin
            if (!c0_ready || axi_araddr !== 28'h100000 || axi_arlen !== 4'd15)
                $fatal(1, "Display AR mismatch");
            ar0_count <= ar0_count + 1;
        end else $fatal(1, "Unexpected AXI ID");
    end

    task automatic response_burst(input [3:0] id, input integer count);
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                @(negedge clk);
                axi_rvalid = 1'b1;
                axi_rlast = (i == count - 1);
                axi_rid = id;
                #1;
                if (id == 0 && (!c0_rvalid || c1_rvalid || c0_rlast !== axi_rlast))
                    $fatal(1, "Display response routing failed");
                if (id == 1 && (!c1_rvalid || c0_rvalid || c1_rlast !== axi_rlast))
                    $fatal(1, "Transform response routing failed");
            end
            @(negedge clk);
            axi_rvalid = 1'b0;
            axi_rlast = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rstn = 1'b1;
        c1_valid = 1'b1;
        for (beat = 0; beat < 4; beat = beat + 1) begin
            c1_addr = beat * 1280;
            @(negedge clk);
        end
        c1_valid = 1'b0;
        c0_valid = 1'b1;
        @(negedge clk);
        c0_valid = 1'b0;
        if (ar1_count != 4 || ar0_count != 1 || !busy)
            $fatal(1, "Four transform bursts and display burst not outstanding");
        response_burst(4'd1, 4);
        response_burst(4'd0, 16);
        repeat (3) response_burst(4'd1, 4);
        if (busy || response_error_count != 0)
            $fatal(1, "Read arbiter failed to drain cleanly: errors=%0d", response_error_count);
        $display("PASS: four outstanding tile rows coexist with a display read");
        $finish;
    end
endmodule

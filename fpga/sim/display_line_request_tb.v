`timescale 1ns / 1ps

module rd_fram_buf (
    input [255:0] wr_data, input [8:0] wr_addr, input wr_en,
    input wr_clk, input wr_rst, input [11:0] rd_addr,
    output [31:0] rd_data, input rd_clk, input rd_rst
);
    assign rd_data = 32'd0;
endmodule

module display_line_request_tb;
    reg ddr_clk = 0, vout_clk = 0;
    always #5 ddr_clk = ~ddr_clk;
    always #7 vout_clk = ~vout_clk;
    reg ddr_rstn = 0, rd_fsync = 0, rd_en = 0;
    reg ddr_rrdy = 0, ddr_rdone = 0;
    wire ddr_rreq, frame_start, frame_complete;
    wire [27:0] ddr_raddr;
    wire [31:0] ddr_rd_len;
    wire [9:0] consumed_gray;
    rd_buf #(.ADDR_WIDTH(28), .ADDR_OFFSET(28'h00c00000),
             .H_NUM(16), .V_NUM(2), .DQ_WIDTH(32),
             .LEN_WIDTH(32), .PIX_WIDTH(32), .LINE_ADDR_WIDTH(22)) dut (
        .ddr_clk(ddr_clk), .ddr_rstn(ddr_rstn),
        .vout_clk(vout_clk), .rd_fsync(rd_fsync), .rd_en(rd_en),
        .vout_de(), .vout_data(), .init_done(1'b1),
        .frame_slot(2'd1), .display_valid(1'b1),
        .frame_start(frame_start), .frame_complete(frame_complete),
        .read_busy_line(), .consumed_gray(consumed_gray),
        .ddr_rreq(ddr_rreq), .ddr_raddr(ddr_raddr),
        .ddr_rd_len(ddr_rd_len), .ddr_rrdy(ddr_rrdy),
        .ddr_rdone(ddr_rdone), .ddr_rdata(256'd0), .ddr_rdata_en(1'b0)
    );

    initial begin
        repeat (5) @(posedge ddr_clk);
        ddr_rstn <= 1;
        repeat (4) @(posedge vout_clk);
        rd_fsync <= 1;
        wait (ddr_rreq);
        if (ddr_raddr !== 28'h01000000 || ddr_rd_len !== 32'd2) begin
            $display("FAIL: first output-pool line address or length"); $fatal(1);
        end
        repeat (12) @(posedge ddr_clk);
        if (!ddr_rreq) begin $display("FAIL: stalled line request was lost"); $fatal(1); end
        ddr_rrdy <= 1;
        @(posedge ddr_clk);
        ddr_rrdy <= 0;
        repeat (4) @(posedge ddr_clk);
        rd_en <= 1;
        repeat (16) @(posedge vout_clk);
        rd_en <= 0;
        wait (ddr_rreq);
        if (ddr_raddr !== 28'h01000000) begin
            $display("FAIL: line offset advanced before completion"); $fatal(1);
        end
        ddr_rdone <= 1;
        #1;
        if (ddr_rreq) begin $display("FAIL: request accepted with stale address"); $fatal(1); end
        @(posedge ddr_clk);
        ddr_rdone <= 0;
        #1;
        if (!ddr_rreq || ddr_raddr !== 28'h01000010) begin
            $display("FAIL: pending line did not use next address"); $fatal(1);
        end
        ddr_rrdy <= 1;
        @(posedge ddr_clk);
        ddr_rrdy <= 0;
        ddr_rdone <= 1;
        @(posedge ddr_clk);
        ddr_rdone <= 0;
        ddr_rrdy <= 1;
        repeat (3) @(posedge ddr_clk);
        if (!frame_complete) begin $display("FAIL: frame completion missing"); $fatal(1); end
        $display("PASS: rd_buf line request holds and advances address after line done");
        $finish;
    end

    initial begin
        repeat (3000) @(posedge ddr_clk);
        $display("FAIL: display line request timeout"); $fatal(1);
    end
endmodule

`timescale 1ns / 1ps

module stage4_demo_fram_buf_tb;
    localparam W=8; localparam H=4; localparam AW=28; localparam DQ=32;
    reg clk=0; always #4 clk=~clk;
    reg rstn=0, fsync=0, de=0;
    wire init_done; wire [3:0] leds; wire out_de; wire [31:0] out_data;
    wire [AW-1:0] awaddr,araddr; wire [3:0] awid,awlen,arid,arlen;
    wire [2:0] awsize,arsize; wire [1:0] awburst,arburst;
    wire awvalid,wvalid,arvalid,rready; wire [DQ*8-1:0] wdata; wire [DQ-1:0] wstrb;

    fram_buf #(.CTRL_ADDR_WIDTH(AW),.MEM_DQ_WIDTH(DQ),.H_NUM(W),.V_NUM(H),.PIX_WIDTH(32)) dut (
        .vin_clk(clk),.wr_fsync(1'b0),.wr_en(1'b0),.wr_data(32'd0),
        .init_done(init_done),.frame_error_led(leds),.ddr_clk(clk),.ddr_rstn(rstn),
        .vout_clk(clk),.rd_fsync(fsync),.rd_en(de),.vout_de(out_de),.vout_data(out_data),
        .axi_awaddr(awaddr),.axi_awid(awid),.axi_awlen(awlen),.axi_awsize(awsize),
        .axi_awburst(awburst),.axi_awready(1'b1),.axi_awvalid(awvalid),
        .axi_wdata(wdata),.axi_wstrb(wstrb),.axi_wlast(1'b0),.axi_wusero_id(4'd0),
        .axi_wvalid(wvalid),.axi_wready(1'b1),.axi_bid(4'd0),
        .axi_araddr(araddr),.axi_arid(arid),.axi_arlen(arlen),.axi_arsize(arsize),
        .axi_arburst(arburst),.axi_arvalid(arvalid),.axi_arready(1'b1),
        .axi_rready(rready),.axi_rdata(256'd0),.axi_rvalid(1'b0),.axi_rlast(1'b0),.axi_rid(4'd0)
    );

    task automatic check;
        input condition; input [8*120-1:0] message;
        begin if(condition!==1'b1) begin $display("FAIL at %0t: %0s",$time,message); $fatal(1); end end
    endtask

    integer row,col,count=0,timeout=0;
    always @(posedge clk) if(out_de) count=count+1;

    initial begin
        repeat(2) @(posedge clk);
        @(negedge clk); rstn=1; fsync=1;
        @(posedge clk); @(negedge clk); fsync=0;
        for(row=0;row<H;row=row+1) begin
            de=1; for(col=0;col<W;col=col+1) @(posedge clk);
            @(negedge clk); de=0; repeat(3) @(posedge clk); @(negedge clk);
        end
        while(count<W*H && timeout<80) begin @(posedge clk); timeout=timeout+1; end
        #1;
        check(count==W*H,"wrapper emitted one complete raster");
        check(init_done,"wrapper reports initialized after DDR reset release");
        check(leds===4'b0111,"input, output and frame milestones set without error LED");
        check(!awvalid&&!wvalid&&!arvalid&&!rready,"Stage 4 demo issues no DDR traffic");
        check(awaddr==0&&araddr==0&&wdata==0&&wstrb==0,"inactive AXI payloads are zero");
        $display("PASS: stage4 demo fram_buf HDMI wrapper and diagnostics test");
        $finish;
    end
endmodule

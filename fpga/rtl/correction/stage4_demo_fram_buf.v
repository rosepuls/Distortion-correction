`timescale 1ns / 1ps

// Drop-in Stage 4 replacement for the vendor demo's fram_buf module.  The
// DDR controller remains initialized by the board top, while this wrapper
// deliberately emits no AXI traffic and displays the algorithm test image.
module fram_buf #(
    parameter MEM_ROW_WIDTH=15,
    parameter MEM_COLUMN_WIDTH=10,
    parameter MEM_BANK_WIDTH=3,
    parameter CTRL_ADDR_WIDTH=MEM_ROW_WIDTH+MEM_BANK_WIDTH+MEM_COLUMN_WIDTH,
    parameter MEM_DQ_WIDTH=32,
    parameter H_NUM=12'd1280,
    parameter V_NUM=12'd720,
    parameter PIX_WIDTH=32
) (
    input vin_clk,
    input wr_fsync,
    input wr_en,
    input [PIX_WIDTH-1:0] wr_data,
    output init_done,
    output [3:0] frame_error_led,
    input ddr_clk,
    input ddr_rstn,
    input vout_clk,
    input rd_fsync,
    input rd_en,
    output vout_de,
    output [PIX_WIDTH-1:0] vout_data,
    output [CTRL_ADDR_WIDTH-1:0] axi_awaddr,
    output [3:0] axi_awid,
    output [3:0] axi_awlen,
    output [2:0] axi_awsize,
    output [1:0] axi_awburst,
    input axi_awready,
    output axi_awvalid,
    output [MEM_DQ_WIDTH*8-1:0] axi_wdata,
    output [MEM_DQ_WIDTH-1:0] axi_wstrb,
    input axi_wlast,
    input [3:0] axi_wusero_id,
    output axi_wvalid,
    input axi_wready,
    input [3:0] axi_bid,
    output [CTRL_ADDR_WIDTH-1:0] axi_araddr,
    output [3:0] axi_arid,
    output [3:0] axi_arlen,
    output [2:0] axi_arsize,
    output [1:0] axi_arburst,
    output axi_arvalid,
    input axi_arready,
    output axi_rready,
    input [MEM_DQ_WIDTH*8-1:0] axi_rdata,
    input axi_rvalid,
    input axi_rlast,
    input [3:0] axi_rid
);
    wire [31:0] demo_pixel;
    wire [19:0] demo_pixel_id;
    wire demo_frame_complete;
    wire demo_input_stall;
    wire demo_sequence_error;
    reg input_seen;
    reg output_seen;
    reg frame_seen;

    stage4_demo_frame_source #(
        .IMAGE_WIDTH(H_NUM),.IMAGE_HEIGHT(V_NUM),.FIFO_DEPTH(16)
    ) source (
        .clk(vout_clk),.rstn(ddr_rstn),.frame_sync(rd_fsync),.active_video(rd_en),
        .pixel_valid(vout_de),.pixel(demo_pixel),.pixel_id(demo_pixel_id),
        .frame_complete(demo_frame_complete),.input_stall(demo_input_stall),
        .sequence_error(demo_sequence_error)
    );

    assign vout_data = demo_pixel[PIX_WIDTH-1:0];
    assign init_done = ddr_rstn;
    // LED4..LED6 become sticky progress markers; LED7 lights on any pipeline error.
    assign frame_error_led = {demo_input_stall | demo_sequence_error,
                              frame_seen, output_seen, input_seen};

    always @(posedge vout_clk) begin
        if (!ddr_rstn) begin
            input_seen <= 1'b0;
            output_seen <= 1'b0;
            frame_seen <= 1'b0;
        end else begin
            if (rd_en) input_seen <= 1'b1;
            if (vout_de) output_seen <= 1'b1;
            if (demo_frame_complete) frame_seen <= 1'b1;
        end
    end

    assign axi_awaddr = {CTRL_ADDR_WIDTH{1'b0}};
    assign axi_awid = 4'd0;
    assign axi_awlen = 4'd0;
    assign axi_awsize = 3'd0;
    assign axi_awburst = 2'd0;
    assign axi_awvalid = 1'b0;
    assign axi_wdata = {(MEM_DQ_WIDTH*8){1'b0}};
    assign axi_wstrb = {MEM_DQ_WIDTH{1'b0}};
    assign axi_wvalid = 1'b0;
    assign axi_araddr = {CTRL_ADDR_WIDTH{1'b0}};
    assign axi_arid = 4'd0;
    assign axi_arlen = 4'd0;
    assign axi_arsize = 3'd0;
    assign axi_arburst = 2'd0;
    assign axi_arvalid = 1'b0;
    assign axi_rready = 1'b0;
endmodule

`timescale 1ns/1ps

module pll(input wire clkin1, output wire clkout0, output wire clkout1,
           output wire clkout2, output wire pll_lock);
    reg [2:0] lock_count = 3'd0;
    always @(posedge clkin1) begin
        if (lock_count != 3'd4)
            lock_count <= lock_count + 1'b1;
    end
    assign clkout0 = clkin1;
    assign clkout1 = clkin1;
    assign clkout2 = clkin1;
    assign pll_lock = (lock_count == 3'd4);
endmodule

module ms72xx_ctl(
    input wire clk, input wire rst_n, output wire init_over,
    output wire iic_tx_scl, inout wire iic_tx_sda,
    output wire iic_scl, inout wire iic_sda
);
    assign init_over = rst_n;
    assign iic_tx_scl = 1'b1;
    assign iic_scl = 1'b1;
    assign iic_tx_sda = 1'bz;
    assign iic_sda = 1'bz;
endmodule

module wr_buf #(
    parameter ADDR_WIDTH=28, ADDR_OFFSET=0, H_NUM=1280, V_NUM=720,
    parameter DQ_WIDTH=32, LEN_WIDTH=32, PIX_WIDTH=24,
    parameter LINE_ADDR_WIDTH=22, FRAME_CNT_WIDTH=6
) (
    input wire ddr_clk, input wire ddr_rstn, input wire wr_clk,
    input wire wr_fsync, input wire wr_en, input wire [PIX_WIDTH-1:0] wr_data,
    input wire rd_bac, output wire ddr_wreq, output wire [ADDR_WIDTH-1:0] ddr_waddr,
    output wire [LEN_WIDTH-1:0] ddr_wr_len, input wire ddr_wrdy,
    input wire ddr_wdone, output wire [8*DQ_WIDTH-1:0] ddr_wdata,
    input wire ddr_wdata_req, output wire [FRAME_CNT_WIDTH-1:0] frame_wcnt,
    output wire frame_wirq
);
    assign ddr_wreq=1'b0; assign ddr_waddr='0; assign ddr_wr_len='0;
    assign ddr_wdata='0; assign frame_wcnt='0; assign frame_wirq=1'b0;
endmodule

module wr_rd_ctrl_top #(
    parameter CTRL_ADDR_WIDTH=28, parameter MEM_DQ_WIDTH=32
) (
    input wire clk, input wire rstn,
    input wire wr_cmd_en, input wire [CTRL_ADDR_WIDTH-1:0] wr_cmd_addr,
    input wire [31:0] wr_cmd_len, output wire wr_cmd_ready, output wire wr_cmd_done,
    output wire wr_bac, input wire [MEM_DQ_WIDTH*8-1:0] wr_ctrl_data,
    output wire wr_data_re,
    input wire rd_cmd_en, input wire [CTRL_ADDR_WIDTH-1:0] rd_cmd_addr,
    input wire [31:0] rd_cmd_len, output wire rd_cmd_ready, output wire rd_cmd_done,
    input wire read_ready, output wire [MEM_DQ_WIDTH*8-1:0] read_rdata,
    output wire read_en,
    output wire [CTRL_ADDR_WIDTH-1:0] axi_awaddr, output wire [3:0] axi_awid,
    output wire [3:0] axi_awlen, output wire [2:0] axi_awsize,
    output wire [1:0] axi_awburst, input wire axi_awready, output wire axi_awvalid,
    output wire [MEM_DQ_WIDTH*8-1:0] axi_wdata,
    output wire [MEM_DQ_WIDTH-1:0] axi_wstrb, input wire axi_wlast,
    output wire axi_wvalid, input wire axi_wready, input wire [3:0] axi_bid,
    input wire [1:0] axi_bresp, input wire axi_bvalid, output wire axi_bready,
    output wire [CTRL_ADDR_WIDTH-1:0] axi_araddr, output wire [3:0] axi_arid,
    output wire [3:0] axi_arlen, output wire [2:0] axi_arsize,
    output wire [1:0] axi_arburst, output wire axi_arvalid, input wire axi_arready,
    output wire axi_rready, input wire [MEM_DQ_WIDTH*8-1:0] axi_rdata,
    input wire axi_rvalid, input wire axi_rlast, input wire [3:0] axi_rid,
    input wire [1:0] axi_rresp
);
    assign wr_cmd_ready=1'b1; assign wr_cmd_done=wr_cmd_en; assign wr_bac=1'b0;
    assign wr_data_re=wr_cmd_en; assign rd_cmd_ready=1'b1; assign rd_cmd_done=rd_cmd_en;
    assign read_rdata=axi_rdata; assign read_en=axi_rvalid;
    assign axi_awaddr='0; assign axi_awid='0; assign axi_awlen='0;
    assign axi_awsize='0; assign axi_awburst='0; assign axi_awvalid=1'b0;
    assign axi_wdata='0; assign axi_wstrb='0; assign axi_wvalid=1'b0;
    assign axi_bready=1'b1; assign axi_araddr='0; assign axi_arid='0;
    assign axi_arlen='0; assign axi_arsize='0; assign axi_arburst='0;
    assign axi_arvalid=1'b0; assign axi_rready=read_ready;
endmodule

module DDR3_50H #(
    parameter DFI_CLK_PERIOD=10000, parameter MEM_ROW_WIDTH=15,
    parameter MEM_COLUMN_WIDTH=10, parameter MEM_BANK_WIDTH=3,
    parameter MEM_DQ_WIDTH=32, parameter MEM_DM_WIDTH=4,
    parameter MEM_DQS_WIDTH=4, parameter REGION_NUM=3,
    parameter CTRL_ADDR_WIDTH=MEM_ROW_WIDTH+MEM_COLUMN_WIDTH+MEM_BANK_WIDTH
) (
    input wire ref_clk, input wire resetn, output wire ddr_init_done,
    output wire ddrphy_clkin, output wire pll_lock,
    input wire [CTRL_ADDR_WIDTH-1:0] axi_awaddr, input wire axi_awuser_ap,
    input wire [3:0] axi_awuser_id, input wire [3:0] axi_awlen,
    output wire axi_awready, input wire axi_awvalid,
    input wire [MEM_DQ_WIDTH*8-1:0] axi_wdata,
    input wire [MEM_DQ_WIDTH-1:0] axi_wstrb, output wire axi_wready,
    output wire [3:0] axi_wusero_id, output wire axi_wusero_last,
    input wire [CTRL_ADDR_WIDTH-1:0] axi_araddr, input wire axi_aruser_ap,
    input wire [3:0] axi_aruser_id, input wire [3:0] axi_arlen,
    output wire axi_arready, input wire axi_arvalid,
    output wire [MEM_DQ_WIDTH*8-1:0] axi_rdata, output wire [3:0] axi_rid,
    output wire axi_rlast, output wire axi_rvalid,
    input wire apb_clk, input wire apb_rst_n, input wire apb_sel,
    input wire apb_enable, input wire [7:0] apb_addr, input wire apb_write,
    output wire apb_ready, input wire [15:0] apb_wdata,
    output wire [15:0] apb_rdata, output wire apb_int,
    output wire [34*MEM_DQS_WIDTH-1:0] debug_data,
    output wire [13*MEM_DQS_WIDTH-1:0] debug_slice_state,
    output wire [21:0] debug_calib_ctrl, output wire [7:0] ck_dly_set_bin,
    input wire force_ck_dly_en, input wire [7:0] force_ck_dly_set_bin,
    output wire [7:0] dll_step, output wire dll_lock,
    input wire [1:0] init_read_clk_ctrl, input wire [3:0] init_slip_step,
    input wire force_read_clk_ctrl, input wire ddrphy_gate_update_en,
    output wire [MEM_DQS_WIDTH-1:0] update_com_val_err_flag,
    input wire rd_fake_stop,
    output wire mem_rst_n, output wire mem_ck, output wire mem_ck_n,
    output wire mem_cke, output wire mem_cs_n, output wire mem_ras_n,
    output wire mem_cas_n, output wire mem_we_n, output wire mem_odt,
    output wire [MEM_ROW_WIDTH-1:0] mem_a,
    output wire [MEM_BANK_WIDTH-1:0] mem_ba,
    inout wire [MEM_DQS_WIDTH-1:0] mem_dqs,
    inout wire [MEM_DQS_WIDTH-1:0] mem_dqs_n,
    inout wire [MEM_DQ_WIDTH-1:0] mem_dq,
    output wire [MEM_DM_WIDTH-1:0] mem_dm
);
    assign ddr_init_done=resetn; assign ddrphy_clkin=ref_clk; assign pll_lock=1'b1;
    assign axi_awready=1'b1; assign axi_wready=1'b1; assign axi_wusero_id='0;
    assign axi_wusero_last=1'b1; assign axi_arready=1'b1; assign axi_rdata='0;
    assign axi_rid='0; assign axi_rlast=1'b0; assign axi_rvalid=1'b0;
    assign apb_ready=1'b1; assign apb_rdata='0; assign apb_int=1'b0;
    assign debug_data='0; assign debug_slice_state='0; assign debug_calib_ctrl='0;
    assign ck_dly_set_bin='0; assign dll_step='0; assign dll_lock=1'b1;
    assign update_com_val_err_flag='0; assign mem_rst_n=resetn;
    assign mem_ck=ref_clk; assign mem_ck_n=~ref_clk; assign mem_cke=1'b1;
    assign mem_cs_n=1'b0; assign mem_ras_n=1'b1; assign mem_cas_n=1'b1;
    assign mem_we_n=1'b1; assign mem_odt=1'b0; assign mem_a='0; assign mem_ba='0;
    assign mem_dqs='z; assign mem_dqs_n='z; assign mem_dq='z; assign mem_dm='0;
endmodule

`timescale 1ns/1ps

module pll(input wire clkin1, output wire clkout0, output wire lock);
    reg [2:0] lock_count = 3'd0;
    always @(posedge clkin1) begin
        if (lock_count != 3'd4)
            lock_count <= lock_count + 1'b1;
    end
    assign clkout0 = clkin1;
    assign lock = (lock_count == 3'd4);
endmodule

// Structural stand-in for the official PG2L200H DDR3 IP.  It exposes the
// Logos2 interface used by pg2l200h_board_top but intentionally does not
// model PHY calibration or SDRAM timing.
module ddr3_test #(
    parameter CTRL_ADDR_WIDTH = 28,
    parameter MEM_ROW_WIDTH = 15,
    parameter MEM_BANK_WIDTH = 3,
    parameter MEM_DQ_WIDTH = 32,
    parameter MEM_DQS_WIDTH = 4
) (
    input wire ref_clk, input wire resetn, output wire core_clk,
    output wire pll_lock, output wire phy_pll_lock, output wire gpll_lock,
    output wire rst_gpll_lock, output wire ddrphy_cpd_lock,
    output wire ddr_init_done,
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
    output wire [15:0] apb_rdata,
    output wire mem_cs_n, output wire mem_rst_n, output wire mem_ck,
    output wire mem_ck_n, output wire mem_cke, output wire mem_ras_n,
    output wire mem_cas_n, output wire mem_we_n, output wire mem_odt,
    output wire [MEM_ROW_WIDTH-1:0] mem_a,
    output wire [MEM_BANK_WIDTH-1:0] mem_ba,
    inout wire [MEM_DQS_WIDTH-1:0] mem_dqs,
    inout wire [MEM_DQS_WIDTH-1:0] mem_dqs_n,
    inout wire [MEM_DQ_WIDTH-1:0] mem_dq,
    output wire [MEM_DQS_WIDTH-1:0] mem_dm,
    input wire dbg_gate_start, input wire dbg_cpd_start,
    input wire dbg_ddrphy_rst_n, input wire dbg_gpll_scan_rst,
    input wire samp_position_dyn_adj,
    input wire [31:0] init_samp_position_even,
    input wire [31:0] init_samp_position_odd,
    input wire wrcal_position_dyn_adj,
    input wire [31:0] init_wrcal_position,
    input wire force_read_clk_ctrl, input wire [15:0] init_slip_step,
    input wire [11:0] init_read_clk_ctrl,
    output wire [33:0] debug_calib_ctrl, output wire [67:0] dbg_slice_status,
    output wire [87:0] dbg_slice_state, output wire [275:0] debug_data,
    output wire [1:0] dbg_dll_upd_state,
    output wire [8:0] debug_gpll_dps_phase,
    output wire [2:0] dbg_rst_dps_state,
    output wire [5:0] dbg_tran_err_rst_cnt,
    output wire dbg_ddrphy_init_fail,
    input wire debug_cpd_offset_adj, input wire debug_cpd_offset_dir,
    input wire [9:0] debug_cpd_offset,
    output wire [9:0] debug_dps_cnt_dir0,
    output wire [9:0] debug_dps_cnt_dir1,
    input wire ck_dly_en, input wire [7:0] init_ck_dly_step,
    output wire [7:0] ck_dly_set_bin, output wire align_error,
    output wire [3:0] debug_rst_state, output wire [3:0] debug_cpd_state
);
    assign core_clk = ref_clk;
    assign ddr_init_done = resetn;
    assign pll_lock = 1'b1;
    assign phy_pll_lock = 1'b1;
    assign gpll_lock = 1'b1;
    assign rst_gpll_lock = 1'b1;
    assign ddrphy_cpd_lock = 1'b1;
    assign axi_awready = 1'b1;
    assign axi_wready = 1'b1;
    assign axi_wusero_id = 4'd0;
    assign axi_wusero_last = 1'b1;
    assign axi_arready = 1'b1;
    assign axi_rdata = {MEM_DQ_WIDTH*8{1'b0}};
    assign axi_rid = 4'd0;
    assign axi_rlast = 1'b0;
    assign axi_rvalid = 1'b0;
    assign apb_ready = 1'b1;
    assign apb_rdata = 16'd0;
    assign mem_rst_n = resetn;
    assign mem_ck = ref_clk;
    assign mem_ck_n = ~ref_clk;
    assign mem_cke = 1'b1;
    assign mem_cs_n = 1'b0;
    assign mem_ras_n = 1'b1;
    assign mem_cas_n = 1'b1;
    assign mem_we_n = 1'b1;
    assign mem_odt = 1'b0;
    assign mem_a = {MEM_ROW_WIDTH{1'b0}};
    assign mem_ba = {MEM_BANK_WIDTH{1'b0}};
    assign mem_dqs = {MEM_DQS_WIDTH{1'bz}};
    assign mem_dqs_n = {MEM_DQS_WIDTH{1'bz}};
    assign mem_dq = {MEM_DQ_WIDTH{1'bz}};
    assign mem_dm = {MEM_DQS_WIDTH{1'b0}};
    assign debug_calib_ctrl = 34'd0;
    assign dbg_slice_status = 68'd0;
    assign dbg_slice_state = 88'd0;
    assign debug_data = 276'd0;
    assign dbg_dll_upd_state = 2'd0;
    assign debug_gpll_dps_phase = 9'd0;
    assign dbg_rst_dps_state = 3'd0;
    assign dbg_tran_err_rst_cnt = 6'd0;
    assign dbg_ddrphy_init_fail = 1'b0;
    assign debug_dps_cnt_dir0 = 10'd0;
    assign debug_dps_cnt_dir1 = 10'd0;
    assign ck_dly_set_bin = 8'd0;
    assign align_error = 1'b0;
    assign debug_rst_state = 4'd0;
    assign debug_cpd_state = 4'd0;
endmodule

module cfg_pll(input wire clkin1, output wire clkout0, output wire lock);
    reg [2:0] lock_count = 3'd0;
    always @(posedge clkin1) begin
        if (lock_count != 3'd4)
            lock_count <= lock_count + 1'b1;
    end
    assign clkout0 = clkin1;
    assign lock = (lock_count == 3'd4);
endmodule

// Functional model: complete HDMI receiver/transmitter configuration as soon
// as the board reset is released.  The real I2C transaction timing belongs to
// PDS/board bring-up rather than a short data-path regression.
module ms72xx_ctl(
    input wire clk, input wire rst_n, output wire init_over_rx,
    output wire init_over, output wire iic_scl, inout wire iic_sda
);
    assign init_over_rx = rst_n;
    assign init_over = rst_n;
    assign iic_scl = 1'b1;
    assign iic_sda = 1'bz;
endmodule

module GTP_INBUFGDS #(
    parameter IOSTANDARD = "DEFAULT",
    parameter TERM_DIFF = "ON"
) (
    output wire O,
    input wire I,
    input wire IB
);
    assign O = I;
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

// Behavioral stand-in for the generated Pango 32-bit-write / 256-bit-read
// line-buffer IP.  Board structural tests use this only when the RGBX writer
// selects its hardware branch; PDS imports the generated wr_fram_buf IP.
module wr_fram_buf (
    input wire [31:0] wr_data,
    input wire [11:0] wr_addr,
    input wire wr_en,
    input wire wr_clk,
    input wire wr_rst,
    output reg [255:0] rd_data,
    input wire [8:0] rd_addr,
    input wire rd_clk,
    input wire rd_rst
);
    reg [31:0] mem [0:4095];
    integer lane;
    always @(posedge wr_clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end
    always @(posedge rd_clk) begin
        if (rd_rst)
            rd_data <= 256'd0;
        else begin
            for (lane = 0; lane < 8; lane = lane + 1)
                rd_data[lane*32 +: 32] <= mem[{rd_addr, 3'b000} + lane];
        end
    end
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

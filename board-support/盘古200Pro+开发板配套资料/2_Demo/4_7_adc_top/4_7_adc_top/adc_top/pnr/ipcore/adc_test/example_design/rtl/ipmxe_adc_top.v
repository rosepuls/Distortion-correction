
/////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2019 PANGO MICROSYSTEMS, INC
// ALL RIGHTS REVERVED.
//
// THE SOURCE CODE CONTAINED HEREIN IS PROPRIETARY TO PANGO MICROSYSTEMS, INC.
// IT SHALL NOT BE REPRODUCED OR DISCLOSED IN WHOLE OR IN PART OR USED BY
// PARTIES WITHOUT WRITTEN AUTHORIZATION FROM THE OWNER.
//
//////////////////////////////////////////////////////////////////////////////

`timescale 1ns/10fs
module ipmxe_adc_top(
    input    wire        apb_clk,
    input    wire        rst_n,


    input    wire       adc_loadsc_n,
    output   wire       adc_clk_out,
    output   wire       cfg_uart_txd,
    input    wire       cfg_uart_rxd
);


localparam  [8:0]  PCLK = 50;


wire  [7:0]    apb_paddr;
wire           apb_psel;
wire           apb_enable;
wire           apb_pwrite;
wire  [15:0]   apb_pwdata;
wire  [15:0]   apb_prdata;
wire           apb_pready;
wire           logic_done_a;
wire           logic_done_b;
wire           adc_dmodified;

wire           over_temp;

wire           user_temp_alarm;

wire           vcc_alarm;

wire           vcca_alarm;

wire           vcc_cram_alarm;

wire           vcc_drm_alarm;

wire           vcc_pu_alarm;

wire           vcca_pu_alarm;

wire           vccio_ddr_alarm;

wire           sync_rst_n;

//uart Interface
pgr_uart_ctrl_top_32bit #(
    .CLK_FREQ          (PCLK         ),
    .FIFO_D            (16           ),
    .WORD_LEN          (2'b11        ),
    .PARITY_EN         (1'b0         ),
    .STOP_LEN          (1'b0         ),
    .MODE              (1'b0         ),
    .AW                (8            ),
    .DW                (16           )
) u_uart_ctrl (
    .rst_n             (sync_rst_n   ),
    .clk               (apb_clk      ),
    .uart_ctrl_sel     (1'b0         ),
    .uart_match        (             ),
    .p_addr            (apb_paddr    ),
    .p_wdata           (apb_pwdata   ),
    .p_ce              (apb_psel     ),
    .p_enable          (apb_enable   ),
    .p_we              (apb_pwrite   ),
    .p_rdy             (apb_pready   ),
    .p_rdata           (apb_prdata   ),
    .mdc               (             ),
    .mdi               (1'b1         ),
    .mdo               (             ),
    .mdo_en            (             ),
    .txd               (cfg_uart_txd ),
    .rxd               (cfg_uart_rxd )
);

adc_test  u_adc(

    .i_rst_n           (sync_rst_n   ),
    .i_apb_clk         (apb_clk      ),
    .i_apb_paddr       (apb_paddr    ),
    .i_apb_psel        (apb_psel     ),
    .i_apb_enable      (apb_enable   ),
    .i_apb_pwrite      (apb_pwrite   ),
    .i_apb_pwdata      (apb_pwdata   ),
    .o_apb_prdata      (apb_prdata   ),
    .o_apb_pready      (apb_pready   ),

    .i_adc_loadsc_n    (adc_loadsc_n ),

    .o_logic_done_a    (logic_done_a  ),
    .o_logic_done_b    (logic_done_b  ),
    .o_adc_clk_out     (adc_clk_out   ),
    .o_adc_dmodified   (adc_dmodified )
);

adc_rst_cross_sync_v1_0 u_rst_n_sync( .clk(apb_clk), .rstn_in(rst_n), .rstn_out(sync_rst_n) );

endmodule

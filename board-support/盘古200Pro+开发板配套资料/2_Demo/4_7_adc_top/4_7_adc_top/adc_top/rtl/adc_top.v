`timescale 1ns / 1ps
/////////////////////////////////////////////////////////////////////////////
//
// Company: 
// Engineer:Will
//
// Create Date:   20:00:00 05/09/2024
// Design Name:   
// Module Name:   adc_top.v
// Project Name:  
// Target Device:  
// Tool versions:  
// Description:  
// Dependencies:
// Revision:
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////

module adc_top(
    input    wire       clk_in      ,
    input    wire       rst_n       ,

    output   reg        led         ,           

    output   wire       cfg_uart_txd,
    input    wire       cfg_uart_rxd 
);

localparam  PCLK = 50;

wire           apb_clk      /* synthesis PAP_MARK_DEBUG="true" */; 
wire  [7:0]    apb_paddr    /* synthesis PAP_MARK_DEBUG="true" */;
wire           apb_psel     /* synthesis PAP_MARK_DEBUG="true" */;
wire           apb_enable   /* synthesis PAP_MARK_DEBUG="true" */;
wire           apb_pwrite   /* synthesis PAP_MARK_DEBUG="true" */;
wire  [15:0]   apb_pwdata   /* synthesis PAP_MARK_DEBUG="true" */;
wire  [15:0]   apb_prdata   /* synthesis PAP_MARK_DEBUG="true" */;
wire           apb_pready   /* synthesis PAP_MARK_DEBUG="true" */;

wire           logic_done_a    ;
wire           logic_done_b    ;
wire           adc_dmodified   ;
wire           user_temp_alarm ;
wire           vcc_alarm       ;
wire           vcca_alarm      ;
wire           vcc_cram_alarm  ;
wire           vcc_drm_alarm   ;
wire           vcc_pu_alarm    ;
wire           vcca_pu_alarm   ;
wire           vccio_ddr_alarm ;
wire           sync_rst_n      ;
reg    [18:0]  led_cnt         ;

//pll
pll u_pll (
  .clkout0 (apb_clk    ),// output 50M
  .lock    (           ),// output
  .clkin1  (clk_in     ) // input 27M
);

//uart2apb
pgr_uart_ctrl_top_32bit #(
    .CLK_FREQ          (PCLK         ),
    .FIFO_D            (16           ),
    .WORD_LEN          (2'b11        ),
    .PARITY_EN         (1'b0         ),
    .STOP_LEN          (1'b0         ),
    .MODE              (1'b0         ),
    .AW                (8            ),
    .DW                (16           )
) uart2apb (
    .rst_n             (sync_rst_n   ),// input
    .clk               (apb_clk      ),// input
    .uart_ctrl_sel     (1'b0         ),// input
    .uart_match        (             ),// output
    .p_addr            (apb_paddr    ),// output[7:0]
    .p_wdata           (apb_pwdata   ),// output[15:0]
    .p_ce              (apb_psel     ),// output
    .p_enable          (apb_enable   ),// output
    .p_we              (apb_pwrite   ),// output
    .p_rdy             (apb_pready   ),// input
    .p_rdata           (apb_prdata   ),// input[15:0]
    .mdc               (             ),// output
    .mdi               (1'b1         ),// input
    .mdo               (             ),// output
    .mdo_en            (             ),// output
    .txd               (cfg_uart_txd ),// output
    .rxd               (cfg_uart_rxd ) // input
);
//adc_ip
adc_test  adc_ip(
    .i_rst_n           (sync_rst_n    ),// input

    .i_apb_clk         (apb_clk       ),// input
    .i_apb_paddr       (apb_paddr     ),// input[7:0]
    .i_apb_psel        (apb_psel      ),// input
    .i_apb_enable      (apb_enable    ),// input
    .i_apb_pwrite      (apb_pwrite    ),// input
    .i_apb_pwdata      (apb_pwdata    ),// input[15:0]
    .o_apb_prdata      (apb_prdata    ),// output[15:0]
    .o_apb_pready      (apb_pready    ),// output

    .i_adc_loadsc_n    (1'b1          ),// input
    .o_logic_done_a    (              ),// output
    .o_logic_done_b    (              ),// output
    .o_adc_clk_out     (adc_clk_out   ),// output 
    .o_adc_dmodified   (              ) // output
);
//rstn
adc_rst_cross_sync_v1_0 rst_n_sync( 
    .clk        (apb_clk     ),//input 
    .rstn_in    (rst_n       ),//input
    .rstn_out   (sync_rst_n  ) //output
);
//led
always @(posedge adc_clk_out)
begin
    if (!sync_rst_n)
        led_cnt  <= 19'd0;
    else
        led_cnt  <= led_cnt + 19'd1;
end

always @(posedge adc_clk_out)
begin
    if (!sync_rst_n)
        led  <= 1'b0;
    else if(&led_cnt)
        led  <= ~led;
end

endmodule

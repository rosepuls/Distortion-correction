//-----------------------------------------------------------------------------
//Date               : 20200916
//Version           : v1.0
//development board  : PG2L100RD02_A0
//Purpose            : LVDS DEMO
//-----------------------------------------------------------------------------
module pgd_ddr_lvds4to1_tx_top #(
   parameter CHAN_N  = 4,
   parameter PATTERN = 4'b1001
) (
     input                  tx_sysclk       ,
     input                  tx_rstn         ,
     input                  tx_ioclk        ,     
     input                  tx_gtp_rstn     ,
     input  [4*CHAN_N-1:0]  tx_data         ,
     output [  CHAN_N-1:0]  tx_data_p       ,
     output [  CHAN_N-1:0]  tx_data_n       ,
     output                 tx_clk_p        ,
     output                 tx_clk_n
);


 wire [  CHAN_N-1:0]  tx_data_o    ;
 wire [  CHAN_N-1:0]  tx_data_t    ;
 wire                 tx_clk_o     ;
 wire                 tx_clk_t     ;
 reg  [7:0]           pattern_clk  ;
   
 
genvar i;
generate 
for(i=0;i<CHAN_N;i=i+1) begin : lvds4to1

wire [7:0] tx_data_d ;
assign tx_data_d = {4'b0000,tx_data[4*i+3:4*i]} ;

GTP_OSERDES_E2 #
(
.GRS_EN ("TRUE"),
. OSERDES_MODE ("DDR4TO1"),
. TSERDES_EN ("FALSE"),
. UPD0_SHIFT_EN ("FALSE"), 
. UPD1_SHIFT_EN ("FALSE"), 
. INIT_SET (2'b00), 
. GRS_TYPE_DQ ("RESET"), 
. LRS_TYPE_DQ0 ("ASYNC_RESET"), 
. LRS_TYPE_DQ1 ("ASYNC_RESET"), 
. LRS_TYPE_DQ2 ("ASYNC_RESET"), 
. LRS_TYPE_DQ3 ("ASYNC_RESET"), 
. GRS_TYPE_TQ ("RESET"), 
. LRS_TYPE_TQ0 ("ASYNC_RESET"), 
. LRS_TYPE_TQ1 ("ASYNC_RESET"), 
. LRS_TYPE_TQ2 ("ASYNC_RESET"), 
. LRS_TYPE_TQ3 ("ASYNC_RESET"), 
. TRI_EN  ("FALSE"),
. TBYTE_EN ("FALSE"), 
. MIPI_EN ("FALSE"), 
. OCASCADE_EN ("FALSE")
) GTP_OSERDES_E2_INST0 (
. RST (~tx_gtp_rstn),
. OCE (1'b1),
. TCE (1'b0),
. OCLKDIV (tx_sysclk),
. SERCLK (tx_ioclk),
. OCLK (tx_ioclk),
. MIPI_CTRL (),
. UPD0_SHIFT (1'b0),
. UPD1_SHIFT (1'b0),
. OSHIFTIN0 (),
. OSHIFTIN1 (),
. DI (tx_data_d),
. TI (),
. TBYTE_IN (),
. OSHIFTOUT0 (),
. OSHIFTOUT1 (),
. DO (tx_data_o[i]),
. TQ ()
);


 GTP_OUTBUFDS  GTP_OUTBUFDS_inst0
 (
    .O (tx_data_p[i]),
    .OB(tx_data_n[i]),
    .I (tx_data_o[i])
 );  
end  
endgenerate  



GTP_OSERDES_E2 #
(
.GRS_EN ("TRUE"),
. OSERDES_MODE ("DDR4TO1"),
. TSERDES_EN ("FALSE"),
. UPD0_SHIFT_EN ("FALSE"), 
. UPD1_SHIFT_EN ("FALSE"), 
. INIT_SET (2'b00), 
. GRS_TYPE_DQ ("RESET"), 
. LRS_TYPE_DQ0 ("ASYNC_RESET"), 
. LRS_TYPE_DQ1 ("ASYNC_RESET"), 
. LRS_TYPE_DQ2 ("ASYNC_RESET"), 
. LRS_TYPE_DQ3 ("ASYNC_RESET"), 
. GRS_TYPE_TQ ("RESET"), 
. LRS_TYPE_TQ0 ("ASYNC_RESET"), 
. LRS_TYPE_TQ1 ("ASYNC_RESET"), 
. LRS_TYPE_TQ2 ("ASYNC_RESET"), 
. LRS_TYPE_TQ3 ("ASYNC_RESET"), 
. TRI_EN  ("FALSE"),
. TBYTE_EN ("FALSE"), 
. MIPI_EN ("FALSE"), 
. OCASCADE_EN ("FALSE")
) GTP_OSERDES_E2_INST0 (
. RST (~tx_gtp_rstn),
. OCE (1'b1),
. TCE (1'b0),
. OCLKDIV (tx_sysclk),
. SERCLK (tx_ioclk),
. OCLK (tx_ioclk),
. MIPI_CTRL (),
. UPD0_SHIFT (1'b0),
. UPD1_SHIFT (1'b0),
. OSHIFTIN0 (),
. OSHIFTIN1 (),
. DI (8'b10101010),
. TI (),
. TBYTE_IN (),
. OSHIFTOUT0 (),
. OSHIFTOUT1 (),
. DO (tx_clk_o),
. TQ ()
);

 

 GTP_OUTBUFDS  GTP_OUTBUFDS_inst2
 (
    .O (tx_clk_p),
    .OB(tx_clk_n),
    .I (tx_clk_o)
 );  

endmodule

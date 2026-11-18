//-----------------------------------------------------------------------------
//Date               : 20200916
//Version           : v1.0
//development board  : PG2L100RD02_A0
//Purpose            : LVDS DEMO
//-----------------------------------------------------------------------------
module pgd_ddr_lvds4to1_rxdata #(
   parameter CHAN_N  = 4
) (
   input                  sysclk          ,
   input                  dbg_key_oper    ,
   input                  rstn_sys        , 
   input                  rx_clk_p        ,
   input                  rx_clk_n        ,
   output                 rx_sysclk       ,
   output                 rx_rstn         ,
   
   input  [  CHAN_N-1:0]  rx_data_p       ,
   input  [  CHAN_N-1:0]  rx_data_n       ,
   output [4*CHAN_N-1:0]  rx_data_t       /*synthesis PAP_MARK_DEBUG="1"*/,
   
   
   input  [2:0]  iodly_ctrl      
);

`ifdef SIM_ON	
	localparam DET_CNT_WIDTH  = 8 ;
    localparam TRG_CNT0_WIDTH = 4 ;
    localparam TRG_CNT1_WIDTH = 4 ;
`else 
	localparam DET_CNT_WIDTH  = 20 ;//20
    localparam TRG_CNT0_WIDTH = 10 ;//10
    localparam TRG_CNT1_WIDTH = 10 ;//10
`endif



 reg  [1:0]	              dbg_key_oper_r  ;
 reg  [DET_CNT_WIDTH-1:0] dbg_key_det_cnt ;
 reg                      dbg_key_oper_act/*synthesis PAP_MARK_DEBUG="1"*/;
 reg  [7:0]				  delay_step_cnt/*synthesis PAP_MARK_DEBUG="1"*/;

wire [CHAN_N-1:0]  rx_data_pn      ;
wire [CHAN_N-1:0]  rx_data_pn_d    ;
wire [CHAN_N-1:0]  rx_data_pn_d0   ;
wire [8*2-1:0]     rx_data_pol   ;


 wire      desclk;
 reg       rx_gate_en;
 reg       rx_rstn_temp;
 reg [1:0] rx_rstn_d;
 reg [7:0] rx_cnt;
 
 wire      rx_ioclk0 ;
 wire      rx_ioclk1 ;
 wire      desclk_d   ;

 wire      rx_ioclk        ;
 reg       rx_gtp_rstn     ;
 wire      rx_sysclk1      ;
 
 wire rx0_idelay ;
 wire rx1_idelay ;
 wire rx2_idelay ;
 wire rx3_idelay ;
 wire rx4_idelay ;

//--------------------------------
//---------rx clk domain ---------
//---------------LVDS CLOCK-------
GTP_INBUFGDS GTP_INBUFGDS_inst
(
  .O (desclk),
  .I (rx_clk_p),
  .IB(rx_clk_n)
);



wire [7:0] delay_step_b/*synthesis PAP_MARK_DEBUG="1"*/ ;
assign delay_step_b = delay_step_cnt/*synthesis PAP_MARK_DEBUG="1"*/;
wire [7:0] delay_step_gray/* synthesis syn_keep=1 */ ;
assign delay_step_gray=((delay_step_b>>1)^delay_step_b);

GTP_IODELAY_E2 #
(
.DELAY_STEP_SEL ("PORT"),//PORT PARAMETER
.DELAY_STEP_VALUE( )
) 
GTP_IODELAY_E2_inst0 (
.DI (desclk),
.DELAY_SEL (1'b1),
.DELAY_STEP (delay_step_gray),
.DO (rx_ioclk)
);


GTP_IOCLKBUF GTP_IOCLKBUF_inst1
(
 .CLKIN(rx_ioclk),
 .DI(1'b1),
 .CLKOUT(rx_ioclk0)
);

GTP_IOCLKDIV_E2 
#(
    .DIV_FACTOR("2")
) GTP_CLKDIV_inst0(
 .CE(1'b1),
 .CLKIN(rx_ioclk),
 .RST_N(rx_gtp_rstn),//rx_gate_en
 .CLKDIVOUT(rx_sysclk)
);   



////////////////////////////////////////////////key
always@(posedge sysclk or negedge rstn_sys) begin
  	if(!rstn_sys) dbg_key_det_cnt <= {DET_CNT_WIDTH{1'b0}} ;
	else dbg_key_det_cnt <= dbg_key_det_cnt + 1'b1 ;
  end
  
  always@(posedge sysclk or negedge rstn_sys) begin
  	if(!rstn_sys) dbg_key_oper_r <= 2'b11 ;
  	else if(dbg_key_det_cnt == {DET_CNT_WIDTH{1'b1}}) dbg_key_oper_r <= {dbg_key_oper_r[0], dbg_key_oper} ;
  	else dbg_key_oper_r[1] <= dbg_key_oper_r[0];	
  end
 always@(posedge sysclk or negedge rstn_sys) begin
  	if(!rstn_sys) dbg_key_oper_act <= 1'b0 ;
  	else dbg_key_oper_act <= dbg_key_oper_r[1] & !dbg_key_oper_r[0];
  end


  always@(posedge sysclk ) begin
  	
  	if(dbg_key_oper_act ==1'b1)
  		delay_step_cnt <= delay_step_cnt +1'b1;
  end

//------------------------------------------
 always @(posedge sysclk or negedge rstn_sys)
     if(!rstn_sys)
         rx_cnt <= 8'h0;
     else if(rx_cnt == 8'hff)
         rx_cnt <= rx_cnt;
     else
         rx_cnt <= rx_cnt + 8'h1;
  
 always @(posedge sysclk or negedge rstn_sys)
     if(!rstn_sys)
         rx_gate_en <= 1'b1;
     else if(rx_cnt >= 8'hf && rx_cnt <= 8'hf0)
         rx_gate_en <= 1'b0; 
     else
         rx_gate_en <= 1'b1; 
 
 always @(posedge sysclk or negedge rstn_sys)
     if(!rstn_sys)
         rx_gtp_rstn <= 1'b1; 
     else if(rx_cnt >= 8'h4f && rx_cnt <= 8'h8f) 
         rx_gtp_rstn <= 1'b0; 
     else
         rx_gtp_rstn <= 1'b1;  

//tx_rstn_temp
  always @(posedge sysclk or negedge rstn_sys)
     if(!rstn_sys)
         rx_rstn_temp <= 1'b0;
     else if(rx_cnt >= 8'hff)
         rx_rstn_temp <= 1'b1; 
     else
         rx_rstn_temp <= 1'b0;

 always @(posedge rx_sysclk or negedge rstn_sys)
 begin 
    if (!rstn_sys)
       rx_rstn_d <= 2'b00 ;
    else
       rx_rstn_d <= {rx_rstn_d[0],rx_rstn_temp};
 end
  
  assign  rx_rstn = rx_rstn_d; 
//---------------------------------------------------------
genvar i;
generate 
for (i=0;i<CHAN_N;i=i+1) begin : lvds1to4 
GTP_INBUFDS u_GTP_INBUFDS
(
  .O (rx_data_pn[i]),
  .I (rx_data_p[i] ),
  .IB(rx_data_n[i] )
);

wire [7:0] rxdata_temp /*synthesis PAP_MARK_DEBUG="1"*/;
assign rx_data_t[4*i+3:4*i] = {rxdata_temp[0],rxdata_temp[1],rxdata_temp[2],rxdata_temp[3]} ;


GTP_ISERDES_E2 #
(
.ISERDES_MODE ("DDR1TO4"), 
.CASCADE_MODE("MASTER"),
.BITSLIP_EN("FALSE"),
.GRS_EN ("TRUE"),
.NUM_ICE(1'b0),
.GRS_TYPE_Q0("RESET"),
.GRS_TYPE_Q1("RESET"),
.GRS_TYPE_Q2("RESET"),
.GRS_TYPE_Q3("RESET"),
.LRS_TYPE_Q0("ASYNC_RESET"),
.LRS_TYPE_Q1("ASYNC_RESET"),
.LRS_TYPE_Q2("ASYNC_RESET"),
.LRS_TYPE_Q3("ASYNC_RESET")
) gtp_iserdes_inst0 (
.RST(~rx_gtp_rstn),
.ICE0(1'b1),
.ICE1(1'b0),
.DESCLK (rx_ioclk0),
.ICLK (rx_ioclk0),
.ICLKDIV(rx_sysclk),
.DI (rx_data_pn[i]),
.BITSLIP(),
.ISHIFTIN0(),
.ISHIFTIN1(),
.IFIFO_WADDR(),
.IFIFO_RADDR(),
.DO(rxdata_temp),
.ISHIFTOUT0(),
.ISHIFTOUT1()
);


end  
endgenerate  

//------------------------------------------------------
endmodule

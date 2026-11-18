//-----------------------------------------------------------------------------
//Date               : 20200916
//Version           : v1.0
//development board  : PG2L100RD02_A0
//Purpose            : LVDS DEMO
//-----------------------------------------------------------------------------
module pgd_clk_rst_gen
(
  //system signal
  input        ref_clk     ,
  input        rstn_in     ,
  output       sysclk      ,
  output       rstn_sys    ,       
  //tx clk
  output       tx_sysclk   ,
  output       tx_ioclk    ,
  output       tx_rstn     ,
  output reg   tx_gtp_rstn    
);

 wire serclk     ;
 wire rstn       ;
 wire pll_lock   ;
 reg [1:0] rstn_d;
 reg [1:0] lock_d;
 reg       tx_rstn_temp;
 reg [1:0] tx_rstn_d;
 reg [7:0] tx_cnt ;
 reg       tx_gate_en;

//sync rstn_in
 always @(posedge sysclk or negedge rstn_in)
     if(!rstn_in)
         rstn_d <= 2'b0;
     else 
         rstn_d <= {rstn_d[0],1'b1};
         
 assign rstn = rstn_d[1];
  
 always @(posedge sysclk or negedge rstn)
     if(!rstn)
         lock_d <= 2'b0;
     else
         lock_d <= {lock_d[0],pll_lock};
         
 assign rstn_sys = lock_d[1];                 
//-----------------------------
//------- tx clk domain -------

pll_tx pll_tx_inst (
    .clkin1(ref_clk),
    .lock(pll_lock),
    .clkout0(serclk),
    .clkout1(sysclk)
);

GTP_IOCLKBUF GTP_IOCLKBUF_inst0
(
 .CLKIN(serclk),
 .DI(1'b1),
 .CLKOUT(tx_ioclk)
);

GTP_IOCLKDIV_E2 
#(
    .DIV_FACTOR("2")
) GTP_CLKDIV_inst0(
 .CE(1'b1),
 .CLKIN(serclk),
 .RST_N(tx_gtp_rstn),
 .CLKDIVOUT(tx_sysclk)
);   

 always @(posedge sysclk or negedge rstn_sys)
     if(!rstn_sys)
         tx_cnt <= 8'h0;
     else if(tx_cnt == 8'hff)
         tx_cnt <= tx_cnt;
     else
         tx_cnt <= tx_cnt + 8'h1;
  
 always @(posedge sysclk or negedge rstn_sys)
     if(!rstn_sys)
         tx_gate_en <= 1'b1;
     else if(tx_cnt >= 8'hf && tx_cnt <= 8'hf0)
         tx_gate_en <= 1'b0; 
     else
         tx_gate_en <= 1'b1; 
 
 always @(posedge sysclk or negedge rstn_sys)
     if(!rstn_sys)
         tx_gtp_rstn <= 1'b1; 
     else if(tx_cnt >= 8'h4f && tx_cnt <= 8'h8f) 
         tx_gtp_rstn <= 1'b0; 
     else
         tx_gtp_rstn <= 1'b1;  

//tx_rstn_temp
  always @(posedge sysclk or negedge rstn_sys)
     if(!rstn_sys)
         tx_rstn_temp <= 1'b0;
     else if(tx_cnt >= 8'hff)
         tx_rstn_temp <= 1'b1; 
     else
         tx_rstn_temp <= 1'b0;
  
  always @(posedge tx_sysclk)
       tx_rstn_d <= {tx_rstn_d[0],tx_rstn_temp};
  
  assign  tx_rstn = tx_rstn_d;                        
       
endmodule
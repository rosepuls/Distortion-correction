//-----------------------------------------------------------------------------
//Date               : 20200916
//Version           : v1.0
//development board  : PG2L100RD02_A0
//Purpose            : LVDS DEMO
//-----------------------------------------------------------------------------

`timescale 1ns/1ps
module pgr_lvds4to1_tb ;
   reg                          rstn_in  ;
   reg				            ref_clk  ;
   wire         [3:0]           tx_data_p;  
   wire         [3:0]           tx_data_n;  
   wire                         tx_clk_p ;
   wire                         tx_clk_n ;
   wire                         err_flag ;
   reg          [1:0]          tx_mode;


initial
begin
   #0 ref_clk=1'b1; 
    end


always #10 ref_clk=~ref_clk;

  
initial
begin
     rstn_in = 1'b0;
     tx_mode = 2'b00;
     #20  
     rstn_in = 1'b1;
     tx_mode = 2'b00;
     #2000
     tx_mode = 2'b00;
     #3000
     tx_mode = 2'b00;
     #4000
     tx_mode = 2'b00;
end

pgd_ddr_lvds4to1_top #(
    .CHAN_N (4),
    .PATTERN(4'b1001) 
) dut(
    .ref_clk     (ref_clk)      ,
    .rstn_in     (rstn_in)      ,
    .tx_mode     (tx_mode )        ,
    .tx_data_p   (tx_data_p)    ,
    .tx_data_n   (tx_data_n)    ,
    .tx_clk_p    (tx_clk_p)     ,
    .tx_clk_n    (tx_clk_n)     ,
    .rx_data_p   (tx_data_p)    ,
    .rx_data_n   (tx_data_n)    ,
    .rx_clk_p    (tx_clk_p)     ,
    .rx_clk_n    (tx_clk_n)     ,
    .err_flag    (err_flag)    ,  
    .dbg_key_oper    (1'b1)               
);
	
		GTP_GRS GRS_INST
	(
		.GRS_N 			(1'b1		)
	);

endmodule

















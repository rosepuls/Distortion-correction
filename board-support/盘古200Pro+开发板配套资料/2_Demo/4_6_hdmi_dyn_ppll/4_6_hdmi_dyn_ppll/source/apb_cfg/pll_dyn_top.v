//////////////////////////////////////////////////////////////////////////////////
// Company:Meyesemi 
// Engineer: 
// 
// Create Date: 2024-11-22  
// Design Name: 
// Module Name: pll_dyn_top
// Project Name: hdmi_dyn_ppll
// Target Devices: Pango PG2L100H-6FBG676
// Tool Versions: PDS 2022.2-SP6.4
// Description: Dynamically control the resolution of HDMI 
//      
// Dependencies: 
// 
// Revision:
// Revision 1.0 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
module pll_dyn_top(
input             clk,
input             rst_n,
input             rstn_key,
input			  cfg_en,
input    [7:0]    key_cnt,
output            pix_clk,
output            pll_lock
 	
);


// 
wire    sys_rst_n;

sys_rst sys_rst_inst(
    .clk      (clk        ),
    .rst_n    (rstn_key      ),
    .sys_rst_n(sys_rst_n  )
   );


//---------------------------------------------------------------------------------------
wire            apb_cfg_clkout0    ; 
wire            apb_cfg_clkout1    ; 
wire            apb_cfg_clkout2    ;  
wire            apb_cfg_lock       ; 
wire            apb_ready          ;
wire  [15:0]    apb_rdata      /* synthesis syn_preserve = 1 */    ;  
wire  [4:0]     apb_addr           ;
wire            apb_sel            ; 
wire            apb_en             ; 
wire            apb_write          ; 
wire  [15:0]    apb_wdata          ; 
//wire            cfg_en             ;
wire            abp_cfg_rst        ;
wire            cfg_start;
wire            cfg_done;
reg led_r;
 assign pll_lock=apb_cfg_lock;
assign test = |apb_rdata;
//--------------------------------------------

dyn_pll dyn_pll(
  .clkout0    (apb_cfg_clkout0    ),// output
  .lock       (apb_cfg_lock       ),// output
  .apb_ready  (apb_ready          ),// output
  .apb_rdata  (apb_rdata          ),// output [15:0]
  .clkin1     (clk                ),// input
  .rst        (~sys_rst_n||abp_cfg_rst || !rstn_key),// input
  .apb_clk    (clk                ),// input
  .apb_rst_n  (sys_rst_n          ),// input
  .apb_addr   (apb_addr           ),// input [4:0]
  .apb_sel    (apb_sel            ),// input
  .apb_en     (apb_en             ),// input
  .apb_write  (apb_write          ),// input
  .apb_wdata  (apb_wdata          ) // input [15:0]
);


//wire    [3:0]    cstate;
//wire    [3:0]    nstate;
apb_cfg apb_cfg(
    .clk	      (clk    ),
    .rst_n	      (sys_rst_n  ),
    .key_cnt      (key_cnt),
    .apb_rdy      (apb_ready  ),
    .apb_rdata    (apb_rdata  ),  
    .apb_addr     (apb_addr   ),
    .apb_sel      (apb_sel    ), 
    .apb_en       (apb_en     ), 
    .apb_write    (apb_write  ),
    .apb_wdata    (apb_wdata  ),
    .cfg_en		  (cfg_en     ),
    .abp_cfg_rst  (abp_cfg_rst),
    .cfg_start    (cfg_start  ),
    .cfg_done 	  (cfg_done   ),
    .cstate       (cstate     ),
    .nstate       (nstate     )
);

assign   pix_clk =  apb_cfg_clkout0;
assign   lock0 =  apb_cfg_lock; 
//for test





endmodule
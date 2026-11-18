//////////////////////////////////////////////////////////////////////////////////
// Company:Meyesemi 
// Engineer: 
// 
// Create Date: 2024-11-22  
// Design Name: hdmi_dyn_ppll
// Module Name: hdmi_dyn_ppll
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
`define UD #1

module hdmi_dyn_ppll(
    input wire        sys_clk       ,// input system clock 27MHz   
    input             rstn_key      , 
    input             key           ,
    output            rstn_out      ,
    output            iic_tx_scl    ,
    inout             iic_tx_sda    ,
    output            led_int       ,
    output            lock_led      ,

//hdmi_out 
    output            pix_clk       ,//pixclk                           
    output            vs_out        , 
    output            hs_out        , 
    output            de_out        ,
    output     [7:0]  r_out         , 
    output     [7:0]  g_out         , 
    output     [7:0]  b_out         
);

parameter   X_WIDTH = 4'd12;
parameter   Y_WIDTH = 4'd12;    


wire                        cfg_clk    ;
wire                        locked     ;
wire                        rstn       ;
wire                        init_over  ;
reg  [15:0]                 rstn_1ms   ;
wire [X_WIDTH - 1'b1:0]     act_x      ;
wire [Y_WIDTH - 1'b1:0]     act_y      ;    
wire                        hs         ;
wire                        vs         ;
wire                        de         ;
wire [12:0]                 v_act      ;
wire [12:0]                 h_act      ;
reg  [3:0]                  reset_delay_cnt;

wire clk ;
wire pll_lock ;
wire lock ;

static_pll static_pll (
  .clkout0(cfg_clk),    // output
  .lock(locked),          // output
  .clkin1(sys_clk)       // input
);

ms72xx_ctl ms72xx_ctl(
    .clk         (  cfg_clk    ), //input       clk,
    .rst_n       (  rstn_out   ), //input       rstn,
                            
    .init_over   (  init_over  ), //output      init_over,
    .iic_tx_scl  (  iic_tx_scl ), //output      iic_scl,
    .iic_tx_sda  (  iic_tx_sda ), //inout       iic_sda
    .iic_scl     (  iic_scl    ), //output      iic_scl,
    .iic_sda     (  iic_sda    )  //inout       iic_sda
);
assign    led_int    =     init_over;
    
always @(posedge cfg_clk)
begin
	if(!locked)
	    rstn_1ms <= 16'd0;
	else
	begin
		if(rstn_1ms == 16'h2710)
		    rstn_1ms <= rstn_1ms;
		else
		    rstn_1ms <= rstn_1ms + 1'b1;
	end
end

assign rstn_out = (rstn_1ms == 16'h2710);
wire [7:0]key_cnt;
reg [7:0]key_cnt_1d;
key_ctl key_ctl
    (
    .clk(sys_clk),    // input
    .key(key),    // input
    .key_deb(key_deb),
    .key_cnt(key_cnt)   // output[7:0]
);
always @(posedge sys_clk)
begin
    key_cnt_1d<=key_cnt;
end

pll_dyn_top pll_dyn_top
    (
    .clk(sys_clk),        // input
    .rst_n(rstn_key),    // input
    .rstn_key(rstn_key),
    .cfg_en(key_cnt_1d!=key_cnt),  // input
    .key_cnt(key_cnt),
    .pix_clk(pix_clk),     // output
    .pll_lock(lock_led)
);


sync_vg sync_vg                                         
(                                                 
    .clk                  (  pix_clk              ),//input                   clk,                                 
    .rstn                 (  rstn_key             ),//input                   rstn,    
    .key_cnt              (  key_cnt              ),                        
    .vs_out               (  vs                   ),//output reg              vs_out,                                                                                                                                      
    .hs_out               (  hs                   ),//output reg              hs_out,            
    .de_out               (  de                   ),//output reg              de_out,             
    .x_act                (  act_x                ),//output reg [X_BITS-1:0] x_out,             
    .y_act                (  act_y                ), //output reg [Y_BITS:0]   y_out,   
    .v_act                (  v_act                ),
    .h_act                (  h_act                )          
);

pattern_vg #(
    .COCLOR_DEPP          (  8                    ), // Bits per channel
    .X_BITS               (  X_WIDTH              ),
    .Y_BITS               (  Y_WIDTH              )
) // Number of fractional bits for ramp pattern
pattern_vg (
    .rstn                 (  rstn_key             ),//input                         rstn,                                                     
    .pix_clk              (  pix_clk              ),//input                         clk_in,  
    .act_x                (  act_x                ),//input      [X_BITS-1:0]       x,   
    .v_act                (  v_act                ),
    .h_act                (  h_act                ),
    // input video timing
    .vs_in                (  vs                   ),//input                         vn_in                        
    .hs_in                (  hs                   ),//input                         hn_in,                           
    .de_in                (  de                   ),//input                         dn_in,
    // test pattern image output                                                    
    .vs_out               (  vs_out               ),//output reg                    vn_out,                       
    .hs_out               (  hs_out               ),//output reg                    hn_out,                       
    .de_out               (  de_out               ),//output reg                    den_out,                      
    .r_out                (  r_out                ),//output reg [COCLOR_DEPP-1:0]  r_out,                      
    .g_out                (  g_out                ),//output reg [COCLOR_DEPP-1:0]  g_out,                       
    .b_out                (  b_out                ) //output reg [COCLOR_DEPP-1:0]  b_out   
);

endmodule

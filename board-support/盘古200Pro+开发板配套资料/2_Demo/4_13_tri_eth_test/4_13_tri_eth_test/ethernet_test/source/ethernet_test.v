`timescale 1ns/1ns
module ethernet_test
(
    input        sys_clk        ,
    input        sys_rst_n      ,
    output [1:0] status_led     ,
    output       led_test       ,
    output       phy_rstn       ,

    output       mdc              /*synthesis PAP_MARK_DEBUG="1"*/,
    inout        mdio             /*synthesis PAP_MARK_DEBUG="1"*/

);
assign led_test = 1'd0;
wire    clk_50m;
pll_gen pll_gen_inst (
  .clkout0(clk_50m),    // output
  .lock(lock),          // output
  .clkin1(sys_clk)       // input
);

wire    [1:0]    eth_status;
mdio_ctrl#(
    .MDC_120MS                 (  5000_000           ) //parameter MDC_120MS    = 1000_000                  //mdc???????120ms??????       
) mdio_ctrl (                                                   
    .i_clk                     (  clk_50m           ),//input                       i_clk                  ,//mdc
    .i_rst_n                   (  sys_rst_n         ),//input                       i_rst_n                ,
                                                     
    .mdc                       (   mdc               ),//output                      mdc                    ,
    .mdio                      (   mdio              ),//inout                       mdio                   ,
                                                     
    .eth_status                (  eth_status         ) //output  reg [1:0]           eth_status              //{link,duplex,speed}
);
assign status_led = eth_status;
assign phy_rstn = sys_rst_n;
    
endmodule

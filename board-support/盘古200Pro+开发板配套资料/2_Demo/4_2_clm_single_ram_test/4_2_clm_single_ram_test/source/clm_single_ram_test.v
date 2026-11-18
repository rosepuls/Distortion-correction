`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Company: meyesemi
// Engineer: aira
//
// Create Date:   2024/5/11  15:50:18
// Design Name:   
// Module Name:   clm_single_ram_test.v
// Project Name:  clm_single_ram_test
// Target Device:  
// Tool versions:  Pango Design Suite 2022.2-SP6.4
// Description:  
//
//
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////
  `define UD #1

module clm_single_ram_test (
    input             clk ,
    input             rst_n ,
    output      [1:0] IP_rd_data /* synthesis PAP_MARK_DEBUG="true" */,
    output      [1:0] GTP_rd_data /* synthesis PAP_MARK_DEBUG="true" */
);


reg [4:0]cnt ;
reg [1:0]data ;
reg rw_ctrl ;


always @(posedge clk ) begin
    if (~rst_n)
        cnt <= 5'd0 ;
    else 
        cnt <= cnt + 5'd1 ;
end

always @(posedge clk ) begin
    if (~rst_n)
        data <= 2'd0 ;
    else if (rw_ctrl)
        data <= data + 2'd1 ;
    else 
        data <= data ;
end

always @(posedge clk ) begin
    if (~rst_n)
        rw_ctrl <= 1'b0 ;
    else if (cnt == 5'd31)
        rw_ctrl <= ~rw_ctrl ;
    else 
        rw_ctrl <= rw_ctrl ;
end

wire [4:0]IP_addr       /* synthesis PAP_MARK_DEBUG="true" */;
wire [1:0]IP_wr_data    /* synthesis PAP_MARK_DEBUG="true" */;
wire IP_wr_en           /* synthesis PAP_MARK_DEBUG="true" */;

assign IP_addr = cnt ;
assign IP_wr_data = data ;
assign IP_wr_en = rw_ctrl ;

clm_single_ram_test_ip my_ip (
  .wr_data              (IP_wr_data ),                        // input [1:0]
  .addr                 (IP_addr    ),                        // input [4:0]
  .clk                  (clk  ),                        // input
  .wr_en                (IP_wr_en   ),                        // input
  .rst                  (~rst_n     ),                        // input
  .rd_data              (IP_rd_data )                         // output [1:0]
);



wire [4:0]GTP_addr      /* synthesis PAP_MARK_DEBUG="true" */;
wire [1:0]GTP_wr_data   /* synthesis PAP_MARK_DEBUG="true" */;
wire GTP_we             /* synthesis PAP_MARK_DEBUG="true" */;

assign GTP_addr = cnt ;
assign GTP_wr_data = data ;
assign GTP_we = rw_ctrl ;

GTP_RAM32X2SP #(
    .INIT_0('b00000000000000000000000000000000),
    .INIT_1('b00000000000000000000000000000000)
) my_GTP (
    .DO                 (GTP_rd_data),                        // OUTPUT[1:0]  
    .ADDR               (GTP_addr   ),                        // INPUT[4:0]  
    .DI                 (GTP_wr_data),                        // INPUT[1:0]  
    .WCLK               (clk  ),                        // INPUT  
    .WE                 (GTP_we     )                         // INPUT  
);



endmodule 
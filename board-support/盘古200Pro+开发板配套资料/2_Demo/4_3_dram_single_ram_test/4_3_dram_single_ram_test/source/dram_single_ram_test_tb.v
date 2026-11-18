`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Company: meyesemi
// Engineer: aira
//
// Create Date:   2024/5/11  15:54:57
// Design Name:   
// Module Name:   dram_single_ram_test_tb.v
// Project Name:  dram_single_ram_test
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

module dram_single_ram_test_tb ();

    localparam T_CLK_PERIOD  = 20  ;      
    localparam T_RST_TIME    = 200 ;      

reg clk ;
reg rst_n ;
wire [7:0] IP_rd_data ;
wire [7:0] GTP_rd_data ;

wire GRS_N;

initial
begin
    clk = 0;
    forever #(T_CLK_PERIOD/2)  clk = ~clk;
end

initial begin
    rst_n = 0 ;
    #T_RST_TIME 
    rst_n = 1 ;
end

GTP_GRS GRS_INST (

.GRS_N(1'b1)

);

dram_single_ram_test u_dram_single_ram_test(
    .clk             (clk ) ,                                       
    .rst_n           (rst_n ) ,                                       
    .IP_rd_data      (IP_rd_data ) ,                                               
    .GTP_rd_data     (GTP_rd_data )                                              
);

    
endmodule


//////////////////////////////////////////////////////////////////////////////////
// Company:Meyesemi 
// Engineer: 
// 
// Create Date: 2024-11-22  
// Design Name: 
// Module Name: sys_rst
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
module sys_rst(
    input    clk,
    input    rst_n,
    output   sys_rst_n
   );

reg    [31:0]    rst_cnt;
reg              sys_rst_r;

always @ (posedge clk or negedge rst_n)
    if(~rst_n)begin
        rst_cnt<=0;
    end
//    else if(rst_cnt=='d1_0000_0000)begin
    else if(rst_cnt=='d10)begin
        rst_cnt<=rst_cnt;
    end
    else begin
        rst_cnt<=rst_cnt+1;
    end

always @ (posedge clk or negedge rst_n)
    if(~rst_n)begin
        sys_rst_r<=0;
    end
//    else if(rst_cnt=='d1_0000_0000)begin
    else if(rst_cnt=='d10)begin
         sys_rst_r<=1;
    end
    else begin
        sys_rst_r<=0;
    end

assign    sys_rst_n=sys_rst_r;

endmodule
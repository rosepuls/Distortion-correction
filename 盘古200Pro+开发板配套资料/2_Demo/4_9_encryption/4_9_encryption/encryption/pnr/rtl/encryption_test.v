/////////////////////////////////////////////////////////////////////////////
//
// Company: 
// Engineer:Will
//
// Create Date:   20:00:00 05/09/2024
// Design Name:   
// Module Name:   
// Project Name:  
// Target Device:  
// Tool versions:  
// Description:  
// Dependencies:
// Revision:
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////
`define LED0 
//`define LED1 
//`define LED2 
module encryption_test(
input               clk_in              ,
input               rst_n               ,
output  [7:0]       led                     
);
reg         [7:0]   led_reg                 ;
reg         [23:0]  led_cnt                 ;

//-----------------------------------------------------------
assign led  = led_reg   ;
`ifdef LED0//Á÷Ë®µÆ
always @ (posedge clk_in)
begin
    if (rst_n==1'b0)     
        led_cnt <= 24'b0; 
    else
        led_cnt <= led_cnt + 1'b1; 
end

always @ (posedge clk_in)
begin
    if (rst_n==1'b0)     
        led_reg <= 8'b0000_0001; 
    else if(&led_cnt)
        led_reg <= {led_reg[6:0],led_reg[7]}; 
end
`elsif LED1//ÉÁË¸
always @ (posedge clk_in)
begin
    if (rst_n==1'b0)     
        led_cnt <= 24'b0; 
    else
        led_cnt <= led_cnt + 1'b1; 
end

always @ (posedge clk_in)
begin
    if (rst_n==1'b0)     
        led_reg <= 8'b0000_0000;
    else if(&led_cnt)
        led_reg <= ~led_reg;
end
`elsif LED2//³£ÁÁ
always @ (posedge clk_in)
begin
    if (rst_n==1'b0)     
        led_reg <= 8'b1111_1111;  
    else 
        led_reg <= 8'b1111_1111;
end
`endif
//-----------------------------------------------------------


endmodule

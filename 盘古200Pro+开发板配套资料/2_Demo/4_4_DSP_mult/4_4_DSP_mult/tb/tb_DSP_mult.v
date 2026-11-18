`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Company: my_minieye
// Engineer:Mill
//
// Create Date:   15:21:00 05/11/2024
// Design Name:   
// Module Name:   tb_DSP_mult.v
// Project Name:  
// Target Device:  
// Tool versions:  
// Description:  1 clock latency
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
`timescale 1ns/1ps
  module tb_DSP_mult;
 
   reg         clk;
   reg         rst;

   reg  [29:0] X;
   reg  [17:0] Y;
   wire [47:0] P;

   DSP_mult
  #(
    .X_reg (0),
	.Y_reg (0) 
  )
 uut 
  (
    .clk(clk),
	.rst(rst),
    .X(X),
    .Y(Y),     
    .P(P)
  );
  
     wire GRS_N;

GTP_GRS GRS_INST (

.GRS_N(1'b1)

);

   initial
   begin
    clk = 0;
	rst = 1;
	X = 0;
	Y =0;
	repeat(20)@(posedge clk);
	rst = 0;
   end
   
   always #5 clk = ~clk;
   
   always@(posedge clk)
   begin
    X[24:0] <= X[24:0] + 100;
	Y [17:0] <= Y[17:0] + 33;
   end
   
   endmodule
   
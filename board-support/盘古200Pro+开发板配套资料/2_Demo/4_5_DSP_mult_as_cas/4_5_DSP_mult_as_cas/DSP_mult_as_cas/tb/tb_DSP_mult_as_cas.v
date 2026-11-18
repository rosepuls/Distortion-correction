
`timescale 1ns/1ps
  module tb_DSP_mult_as_cas;
  
   reg         clk;
   reg         rst;

   reg  [29:0] X;
   reg  [17:0] Y;
   wire [47:0] P;
   wire [47:0] CPO; 

   
wire GRS_N;
 
GTP_GRS GRS_INST (

.GRS_N(1'b1)

);
   DSP_mult_as_cas
  #(
    .X_reg (1),
	.Y_reg (1)
  )
 uut 
  (
    .clk(clk),
	.rst(rst),
    .X(X),
    .Y(Y),  
	.P(P),
    .CPO(CPO)

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
	//CPO [47:0] <= CPO[47:0] + 22;
   end
   
   endmodule
   
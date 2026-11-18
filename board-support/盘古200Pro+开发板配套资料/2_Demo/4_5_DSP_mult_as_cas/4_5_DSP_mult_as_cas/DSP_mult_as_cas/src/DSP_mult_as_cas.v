`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Company: my_minieye
// Engineer:Mill
//
// Design Name:   
// Module Name:   DSP_mult_as_cas.v
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
  `define UD #1

  module DSP_mult_as_cas
  #(
    parameter X_reg = 1,
	parameter Y_reg = 1
	
  )

  (
    input            clk,
	input            rst,
    input  [29: 0]   X,      // 30-bit input: X data input
    input  [17: 0]   Y,      // 18-bit input: Y data input
	output [47: 0 ]  P,		// 48-bit output: Primary data output
    output [47: 0 ]  CPO      
  );


GTP_APM_E2 #(
 .GRS_EN ("TRUE"), 
 .USE_POSTADD (1), //使能累加功能
 .USE_PREADD (0), //不使能预加功能
 .PREADD_REG (0), //不使能预加寄存器
 .X_REG (0), 
 .CXO_REG (0), // X级联输出寄存器延迟, 0/1/2/3
 .XB_REG (0),
 .Y_REG (0), 
 .Z_REG (0),
 .MULT_REG (0), 
 .P_REG (1), //不使能累加寄存器
 .MODEY_REG (0), 
 .MODEZ_REG (0), 
 .MODEIN_REG (0), 
 .X_SEL (0), 
 .XB_SEL (0), 
 .ASYNC_RST (0), 
 .USE_SIMD (0), 
 .P_INIT0 (48'd0), 
 .P_INIT1 (48'd0),
 .ROUNDMODE_SEL (0),
 .CPO_REG (0), // COUT,CPO不使能寄存器
 .USE_ACCLOW (0), //累加仅使用低17bit作为反馈不使能
 .CIN_SEL (0) //不选择CPI作为累加的输入
) 
u0_GTP_APM_E2
(
 .P(P),
 .CPO(CPO),
 .COUT(), 
 .CXO(),
 .CXBO(), 
 .X(X),
 .CXI(), 
 .CXBI(), 
 .Y(Y),
 .Z(),
 .CPI(), 
 .CIN(), 
 .XB (),
 .MODEIN(5'b00010), 
 .MODEY(3'b001),
 .MODEZ(4'b0001),
 .CLK(clk),
 .RSTX(rst),
 .RSTXB(rst),
 .RSTY(rst),
 .RSTZ(rst),
 .RSTM(rst),
 .RSTP(rst),
 .RSTPRE(rst),
 .RSTMODEIN(rst),
 .RSTMODEY(rst),
 .RSTMODEZ(rst),
 .CEX1(1'b0),
 .CEX2(1'b0),
 .CEX3(1'b0),
 .CEXB(1'b0),
 .CEY1(1'b0),
 .CEY2(1'b0),
 .CEZ(1'b0),
 .CEM(1'b0),
 .CEP(1'b1),
 .CEPRE(1'b0),
 .CEMODEIN(1'b0),
 .CEMODEY(1'b0),
 .CEMODEZ(1'b0)
); 

   endmodule
   
				
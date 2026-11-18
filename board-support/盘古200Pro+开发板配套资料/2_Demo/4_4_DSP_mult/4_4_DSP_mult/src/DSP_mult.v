`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Company: my_minieye
// Engineer:Mill
//
// Create Date:   15:00:00 05/11/2024
// Design Name:   
// Module Name:   DSP_mult.v
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

  module DSP_mult
  #(
    parameter X_reg = 1,
	parameter Y_reg = 1
	
  )

  (
    input            clk,
	input            rst,
    input  [29: 0]   X,      // 30-bit input: A data input
    input  [17 : 0]  Y,     // 18-bit input: B data input
    output  [47: 0 ] P    // 48-bit output: Primary data output

  );
 



GTP_APM_E2 #(
	.GRS_EN ("TRUE"), 
	.USE_POSTADD (0), //不使能累加功能
	.USE_PREADD (0), //使能预加功能
	.PREADD_REG (0), //不使能预加寄存器
	.X_REG (X_reg),
	.CXO_REG (0), // X级联输出寄存器延迟, 0/1/2/3
	.XB_REG (0),
	.Y_REG (Y_reg), 
	.Z_REG (0), 
	.MULT_REG (1), //使用MULT_REG
	.P_REG (0), //不使能累加寄存器
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
	.CPO_REG (0), // PO,CPO不使能寄存器
	.USE_ACCLOW (0), // 累加仅使用低17bit作为反馈不使能
	.CIN_SEL (0) // 不选择CPI作为累加的输入
	) 
	u0_GTP_APM_E2
	(
	.P(P),
	.CPO(),
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
	.XB (25'd0),
	.MODEIN(5'b00110), 
	.MODEY(3'b000),
	.MODEZ(4'b0000),
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
	.CEM(1'b1),
	.CEP(1'b0),
	.CEPRE(1'b0),
	.CEMODEIN(1'b0),
	.CEMODEY(1'b0),
	.CEMODEZ(1'b0)
);
 
//   DSP48E1   : In order to incorporate this function into the design,
//   Verilog   : the following instance declaration needs to be placed
//  instance   : in the body of the design code.  The instance name
// declaration : (DSP48E1_inst) and/or the port declarations within the
//    code     : parenthesis may be changed to properly reference and
//             : connect this function to the design.  All inputs
//             : and outputs must be connected.

//  <-----Cut code below this line---->

   // DSP48E1: 48-bit Multi-Functional Arithmetic Block
   //          Artix-7
   // Xilinx HDL Language Template, version 14.7
/*
   DSP48E1 #(
      // Feature Control Attributes: Data Path Selection
      .A_INPUT("DIRECT"),               // Selects A input source, "DIRECT" (A port) or "CASCADE" (ACIN port)
      .B_INPUT("DIRECT"),               // Selects B input source, "DIRECT" (B port) or "CASCADE" (BCIN port)
      .USE_DPORT("FALSE"),              // Select D port usage (TRUE or FALSE)
      .USE_MULT("MULTIPLY"),            // Select multiplier usage ("MULTIPLY", "DYNAMIC", or "NONE")
      .USE_SIMD("ONE48"),               // SIMD selection ("ONE48", "TWO24", "FOUR12")
      // Pattern Detector Attributes: Pattern Detection Configuration
      .AUTORESET_PATDET("NO_RESET"),    // "NO_RESET", "RESET_MATCH", "RESET_NOT_MATCH" 
      .MASK(48'h3fffffffffff),          // 48-bit mask value for pattern detect (1=ignore)
      .PATTERN(48'h000000000000),       // 48-bit pattern match for pattern detect
      .SEL_MASK("MASK"),                // "C", "MASK", "ROUNDING_MODE1", "ROUNDING_MODE2" 
      .SEL_PATTERN("PATTERN"),          // Select pattern value ("PATTERN" or "C")
      .USE_PATTERN_DETECT("NO_PATDET"), // Enable pattern detect ("PATDET" or "NO_PATDET")
      // Register Control Attributes: Pipeline Register Configuration
      .ACASCREG(X_reg),                     // Number of pipeline stages between A/ACIN and ACOUT (0, 1 or 2)
      .ADREG(1),                        // Number of pipeline stages for pre-adder (0 or 1)
      .ALUMODEREG(1),                   // Number of pipeline stages for ALUMODE (0 or 1)
      .AREG(X_reg),                         // Number of pipeline stages for A (0, 1 or 2)
      .BCASCREG(B_reg),                     // Number of pipeline stages between B/BCIN and BCOUT (0, 1 or 2)
      .BREG(B_reg),                         // Number of pipeline stages for B (0, 1 or 2)
      .CARRYINREG(1),                   // Number of pipeline stages for CARRYIN (0 or 1)
      .CARRYINSELREG(1),                // Number of pipeline stages for CARRYINSEL (0 or 1)
      .CREG(1),                         // Number of pipeline stages for C (0 or 1)
      .DREG(1),                         // Number of pipeline stages for D (0 or 1)
      .INMODEREG(1),                    // Number of pipeline stages for INMODE (0 or 1)
      .MREG(1),                         // Number of multiplier pipeline stages (0 or 1)
      .OPMODEREG(1),                    // Number of pipeline stages for OPMODE (0 or 1)
      .PREG(1)                          // Number of pipeline stages for P (0 or 1)
   )
   DSP48E1_inst (
      // Cascade: 30-bit (each) output: Cascade Ports
      .ACOUT(ACOUT),                   // 30-bit output: A port cascade output
      .BCOUT(BCOUT),                   // 18-bit output: B port cascade output
      .CARRYCASCOUT(CARRYCASCOUT),     // 1-bit output: Cascade carry output
      .MULTSIGNOUT(MULTSIGNOUT),       // 1-bit output: Multiplier sign cascade output
      .PCOUT(PCOUT),                   // 48-bit output: Cascade output
      // Control: 1-bit (each) output: Control Inputs/Status Bits
      .OVERFLOW(OVERFLOW),             // 1-bit output: Overflow in add/acc output
      .PATTERNBDETECT(PATTERNBDETECT), // 1-bit output: Pattern bar detect output
      .PATTERNDETECT(PATTERNDETECT),   // 1-bit output: Pattern detect output
      .UNDERFLOW(UNDERFLOW),           // 1-bit output: Underflow in add/acc output
      // Data: 4-bit (each) output: Data Ports
      .CARRYOUT(CARRYOUT),             // 4-bit output: Carry output
      .P(P),                           // 48-bit output: Primary data output
      // Cascade: 30-bit (each) input: Cascade Ports
      .ACIN(30'd0),                     // 30-bit input: A cascade data input
      .BCIN(18'd0),                     // 18-bit input: B cascade input
      .CARRYCASCIN(1'b0),       // 1-bit input: Cascade carry input
      .MULTSIGNIN(1'b0),         // 1-bit input: Multiplier sign input
      .PCIN(48'd0),                     // 48-bit input: P cascade input
      // Control: 4-bit (each) input: Control Inputs/Status Bits
      .ALUMODE(4'b000),               // 4-bit input: ALU control input
      .CARRYINSEL(3'b000),         // 3-bit input: Carry select input
      .CLK(clk),                       // 1-bit input: Clock input
      .INMODE(5'b00000),                 // 5-bit input: INMODE control input
      .OPMODE(7'b000_0101),                 // 7-bit input: Operation mode input
      // Data: 30-bit (each) input: Data Ports
      .A(A),                           // 30-bit input: A data input
      .B(B),                           // 18-bit input: B data input
      .C(48'd0),                           // 48-bit input: C data input
      .CARRYIN(1'b0),               // 1-bit input: Carry input signal
      .D(25'd0),                           // 25-bit input: D data input
      // Reset/Clock Enable: 1-bit (each) input: Reset/Clock Enable Inputs
      .CEA1(1'b1),                     // 1-bit input: Clock enable input for 1st stage AREG
      .CEA2(1'b1),                     // 1-bit input: Clock enable input for 2nd stage AREG
      .CEAD(1'b0),                     // 1-bit input: Clock enable input for ADREG
      .CEALUMODE(1'b1),           // 1-bit input: Clock enable input for ALUMODE
      .CEB1(1'b1),                     // 1-bit input: Clock enable input for 1st stage BREG
      .CEB2(1'b1),                     // 1-bit input: Clock enable input for 2nd stage BREG
      .CEC(1'b0),                       // 1-bit input: Clock enable input for CREG
      .CECARRYIN(1'b0),           // 1-bit input: Clock enable input for CARRYINREG
      .CECTRL(1'b1),                 // 1-bit input: Clock enable input for OPMODEREG and CARRYINSELREG
      .CED(1'b0),                       // 1-bit input: Clock enable input for DREG
      .CEINMODE(1'b1),             // 1-bit input: Clock enable input for INMODEREG
      .CEM(1'b1),                       // 1-bit input: Clock enable input for MREG
      .CEP(1'b1),                       // 1-bit input: Clock enable input for PREG
      .RSTA(~rstn),                     // 1-bit input: Reset input for AREG
      .RSTALLCARRYIN(~rstn),   // 1-bit input: Reset input for CARRYINREG
      .RSTALUMODE(~rstn),         // 1-bit input: Reset input for ALUMODEREG
      .RSTB(~rstn),                     // 1-bit input: Reset input for BREG
      .RSTC(~rstn),                     // 1-bit input: Reset input for CREG
      .RSTCTRL(~rstn),               // 1-bit input: Reset input for OPMODEREG and CARRYINSELREG
      .RSTD(~rstn),                     // 1-bit input: Reset input for DREG and ADREG
      .RSTINMODE(~rstn),           // 1-bit input: Reset input for INMODEREG
      .RSTM(~rstn),                     // 1-bit input: Reset input for MREG
      .RSTP(~rstn)                      // 1-bit input: Reset input for PREG
   );
*/
   // End of DSP48E1_inst instantiation
   
   endmodule
   
				
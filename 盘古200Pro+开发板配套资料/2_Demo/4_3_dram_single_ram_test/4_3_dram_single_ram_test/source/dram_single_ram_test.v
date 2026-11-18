`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// Company: meyesemi
// Engineer: aira
//
// Create Date:   2024/5/11  15:54:57
// Design Name:   
// Module Name:   dram_single_ram_test.v
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
  `define UD #1

module dram_single_ram_test(
   input          clk ,
   input          rst_n ,
   output    [7:0]IP_rd_data /* synthesis PAP_MARK_DEBUG="true" */,
   output    [7:0]GTP_rd_data/* synthesis PAP_MARK_DEBUG="true" */     
   );


reg [8:0]cnt ;
reg [7:0]data ;
reg rw_ctrl ;

always @(posedge clk ) begin
   if (~rst_n)
      cnt <= 9'd0 ;
   else 
      cnt <= cnt + 9'd1 ;
end

always @(posedge clk ) begin
   if (~rst_n)
      data <= 8'd0 ;
   else if (rw_ctrl)
      data <= data + 8'd1 ;
   else 
      data <= 8'd0 ;
end

always @(posedge clk ) begin
   if (~rst_n)
      rw_ctrl <= 1'b0 ;
   else if (cnt == 9'd511)
      rw_ctrl <= ~rw_ctrl ;
   else 
      rw_ctrl <= rw_ctrl ;
end



wire [8:0]IP_addr    /* synthesis PAP_MARK_DEBUG="true" */;
wire [7:0]IP_wr_data /* synthesis PAP_MARK_DEBUG="true" */;
wire IP_wr_en        /* synthesis PAP_MARK_DEBUG="true" */;

assign IP_addr = cnt ;
assign IP_wr_data = data ;
assign IP_wr_en = rw_ctrl ;

dram_single_ram_test_ip my_ip (
  .wr_data              (IP_wr_data    ),       // input [7:0]
  .addr                 (IP_addr       ),       // input [8:0]
  .wr_en                (IP_wr_en      ),       // input
  .clk                  (clk          ),       // input
  .rst                  (~rst_n        ),       // input
  .rd_data              (IP_rd_data    )        // output [7:0]
);


wire [13:0]GTP_addr     /* synthesis PAP_MARK_DEBUG="true" */;
wire [7:0]GTP_wr_data   /* synthesis PAP_MARK_DEBUG="true" */;
wire GTP_wr_en        /* synthesis PAP_MARK_DEBUG="true" */;

assign GTP_addr = cnt; // 
assign GTP_wr_data = data ;
assign GTP_wr_en = rw_ctrl ;

wire addra ;
assign addra = {2'b00,GTP_addr,3'b000} ;

GTP_DRM18K_E1 #(
    .GRS_EN("TRUE"),
    .DATA_WIDTH_A(8),
    .DATA_WIDTH_B(8),
    .DOA_REG(0),
    .DOB_REG(0),
    .DOA_REG_CLKINV(0),
    .DOB_REG_CLKINV(0),
    .RSTA_VAL('b000000000000000000),
    .RSTB_VAL('b000000000000000000),
    .RST_TYPE("SYNC"),
    .RAM_MODE("SINGLE_PORT"),
    .WRITE_MODE_A("NORMAL_WRITE"),
    .WRITE_MODE_B("NORMAL_WRITE"),
    .INIT_00(288'b0),
    .INIT_01(288'b0),
    .INIT_02(288'b0),
    .INIT_03(288'b0),
    .INIT_04(288'b0),
    .INIT_05(288'b0),
    .INIT_06(288'b0),
    .INIT_07(288'b0),
    .INIT_08(288'b0),
    .INIT_09(288'b0),
    .INIT_0A(288'b0),
    .INIT_0B(288'b0),
    .INIT_0C(288'b0),
    .INIT_0D(288'b0),
    .INIT_0E(288'b0),
    .INIT_0F(288'b0),
    .INIT_10(288'b0),
    .INIT_11(288'b0),
    .INIT_12(288'b0),
    .INIT_13(288'b0),
    .INIT_14(288'b0),
    .INIT_15(288'b0),
    .INIT_16(288'b0),
    .INIT_17(288'b0),
    .INIT_18(288'b0),
    .INIT_19(288'b0),
    .INIT_1A(288'b0),
    .INIT_1B(288'b0),
    .INIT_1C(288'b0),
    .INIT_1D(288'b0),
    .INIT_1E(288'b0),
    .INIT_1F(288'b0),
    .INIT_20(288'b0),
    .INIT_21(288'b0),
    .INIT_22(288'b0),
    .INIT_23(288'b0),
    .INIT_24(288'b0),
    .INIT_25(288'b0),
    .INIT_26(288'b0),
    .INIT_27(288'b0),
    .INIT_28(288'b0),
    .INIT_29(288'b0),
    .INIT_2A(288'b0),
    .INIT_2B(288'b0),
    .INIT_2C(288'b0),
    .INIT_2D(288'b0),
    .INIT_2E(288'b0),
    .INIT_2F(288'b0),
    .INIT_30(288'b0),
    .INIT_31(288'b0),
    .INIT_32(288'b0),
    .INIT_33(288'b0),
    .INIT_34(288'b0),
    .INIT_35(288'b0),
    .INIT_36(288'b0),
    .INIT_37(288'b0),
    .INIT_38(288'b0),
    .INIT_39(288'b0),
    .INIT_3A(288'b0),
    .INIT_3B(288'b0),
    .INIT_3C(288'b0),
    .INIT_3D(288'b0),
    .INIT_3E(288'b0),
    .INIT_3F(288'b0),
    .INIT_FILE("NONE"),
    .BLOCK_X(0),
    .BLOCK_Y(0),
    .RAM_DATA_WIDTH(9),
    .RAM_ADDR_WIDTH(11),
    .INIT_FORMAT("BIN") 
) my_GTP (
    .ADDRA_HOLD      (1'b0       ),         // INPUT  
    .ADDRB_HOLD      (1'b0       ),         // INPUT  
    .CEA             (1'b1       ),         // INPUT  
    .CEB             (1'b0       ),         // INPUT  
    .CLKA            (clk       ),         // INPUT  
    .CLKB            (           ),         // INPUT  
    .ORCEA           (1'b0       ),         // INPUT  
    .ORCEB           (           ),         // INPUT  
    .RSTA            (~rst_n     ),         // INPUT  
    .RSTB            (           ),         // INPUT  
    .WEA             (GTP_wr_en  ),         // INPUT  
    .WEB             (           ),         // INPUT  
    .DOA             (GTP_rd_data),         // OUTPUT[17:0]  
    .DOB             (           ),         // OUTPUT[17:0]  
    .ADDRA           ({2'b00,GTP_addr,3'b000}),         // INPUT[13:0]  
    .ADDRB           (           ),         // INPUT[13:0]  
    .BWEA            (4'hf       ),         // INPUT[3:0]  
    .BWEB            (           ),         // INPUT[1:0]  
    .DIA             (GTP_wr_data),         // INPUT[17:0]  
    .DIB             (           )          // INPUT[17:0]  
);


endmodule
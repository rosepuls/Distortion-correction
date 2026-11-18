//-----------------------------------------------------------------------------
//Date               : 20200916
//Version           : v1.0
//development board  : PG2L100RD02_A0
//Purpose            : LVDS DEMO
//-----------------------------------------------------------------------------
module prbs_gen #(
parameter PRBS_GEN_EN = 1'b0
)(
input clk,
input rstn,
input clk_en,

input [3:0] cfg_prbs_mode,
input cfg_insert_er,
input [19:0] din,
output [19:0] dout,

input  cfg_error_cnt_clr,
output reg error,
output reg [7:0] error_cnt
);

wire [20:1] Y_PRBS7;
wire [20:1] Y_PRBS15;
wire [20:1] Y_PRBS23;
wire [20:1] Y_PRBS31;
wire [20:1] Y_20UI;
wire [20:1] Y_D10_2;
wire [20:1] Y_LONG1;
wire [20:1] Y_LONG0;
wire [20:1] Y_PCIE;
wire [32:1] X;
reg  poll;
reg  [32:1] latch_y;
reg  [32:1] y_comb;
reg  [3:0]  cfg_insert_er_d;
reg  [20:1] y_all;
reg  [20:1] latch_y_all;
reg  [1:0]  cfg_error_cnt_clr_d;

//PRBS-7: 1 + X6 + X7
assign  Y_PRBS7[20] = X[7] ^ X[6] ^ 1 ;
assign  Y_PRBS7[19] = X[6] ^ X[5] ^ 1 ;
assign  Y_PRBS7[18] = X[5] ^ X[4] ^ 1 ;
assign  Y_PRBS7[17] = X[4] ^ X[3] ^ 1 ;
assign  Y_PRBS7[16] = X[3] ^ X[2] ^ 1 ;
assign  Y_PRBS7[15] = X[2] ^ X[1] ^ 1 ;
assign  Y_PRBS7[14] = X[7] ^ X[6] ^ X[1] ^ 0 ;
assign  Y_PRBS7[13] = X[7] ^ X[5] ^ 1 ;
assign  Y_PRBS7[12] = X[6] ^ X[4] ^ 1 ;
assign  Y_PRBS7[11] = X[5] ^ X[3] ^ 1 ;
assign  Y_PRBS7[10] = X[4] ^ X[2] ^ 1 ;
assign  Y_PRBS7[9]  = X[3] ^ X[1] ^ 1 ;
assign  Y_PRBS7[8]  = X[7] ^ X[6] ^ X[2] ^ 0 ;
assign  Y_PRBS7[7]  = X[6] ^ X[5] ^ X[1] ^ 0 ;
assign  Y_PRBS7[6]  = X[7] ^ X[6] ^ X[5] ^ X[4] ^ 1 ;
assign  Y_PRBS7[5]  = X[6] ^ X[5] ^ X[4] ^ X[3] ^ 1 ;
assign  Y_PRBS7[4]  = X[5] ^ X[4] ^ X[3] ^ X[2] ^ 1 ;
assign  Y_PRBS7[3]  = X[4] ^ X[3] ^ X[2] ^ X[1] ^ 1 ;
assign  Y_PRBS7[2]  = X[7] ^ X[6] ^ X[3] ^ X[2] ^ X[1] ^ 0 ;
assign  Y_PRBS7[1]  = X[7] ^ X[5] ^ X[2] ^ X[1] ^ 1 ;

//PRBS-15: 1 + X14 + X15
assign  Y_PRBS15[20] = X[15] ^ X[14] ^ 1 ;
assign  Y_PRBS15[19] = X[14] ^ X[13] ^ 1 ;
assign  Y_PRBS15[18] = X[13] ^ X[12] ^ 1 ;
assign  Y_PRBS15[17] = X[12] ^ X[11] ^ 1 ;
assign  Y_PRBS15[16] = X[11] ^ X[10] ^ 1 ;
assign  Y_PRBS15[15] = X[10] ^ X[9]  ^ 1 ;
assign  Y_PRBS15[14] = X[9]  ^ X[8]  ^ 1 ;
assign  Y_PRBS15[13] = X[8]  ^ X[7]  ^ 1 ;
assign  Y_PRBS15[12] = X[7]  ^ X[6]  ^ 1 ;
assign  Y_PRBS15[11] = X[6]  ^ X[5]  ^ 1 ;
assign  Y_PRBS15[10] = X[5]  ^ X[4]  ^ 1 ;
assign  Y_PRBS15[9]  = X[4]  ^ X[3]  ^ 1 ;
assign  Y_PRBS15[8]  = X[3]  ^ X[2]  ^ 1 ;
assign  Y_PRBS15[7]  = X[2]  ^ X[1]  ^ 1 ;
assign  Y_PRBS15[6]  = X[15] ^ X[14] ^ X[1] ^ 0 ;
assign  Y_PRBS15[5]  = X[15] ^ X[13] ^ 1 ;
assign  Y_PRBS15[4]  = X[14] ^ X[12] ^ 1 ;
assign  Y_PRBS15[3]  = X[13] ^ X[11] ^ 1 ;
assign  Y_PRBS15[2]  = X[12] ^ X[10] ^ 1 ;
assign  Y_PRBS15[1]  = X[11] ^ X[9 ] ^ 1 ;

//PRBS-23: 1 + X18 + X23
assign  Y_PRBS23[20] = X[23] ^ X[18] ^ 1 ;
assign  Y_PRBS23[19] = X[22] ^ X[17] ^ 1 ;
assign  Y_PRBS23[18] = X[21] ^ X[16] ^ 1 ;
assign  Y_PRBS23[17] = X[20] ^ X[15] ^ 1 ;
assign  Y_PRBS23[16] = X[19] ^ X[14] ^ 1 ;
assign  Y_PRBS23[15] = X[18] ^ X[13] ^ 1 ;
assign  Y_PRBS23[14] = X[17] ^ X[12] ^ 1 ;
assign  Y_PRBS23[13] = X[16] ^ X[11] ^ 1 ;
assign  Y_PRBS23[12] = X[15] ^ X[10] ^ 1 ;
assign  Y_PRBS23[11] = X[14] ^ X[9]  ^ 1 ;
assign  Y_PRBS23[10] = X[13] ^ X[8]  ^ 1 ;
assign  Y_PRBS23[9]  = X[12] ^ X[7]  ^ 1 ;
assign  Y_PRBS23[8]  = X[11] ^ X[6]  ^ 1 ;
assign  Y_PRBS23[7]  = X[10] ^ X[5]  ^ 1 ;
assign  Y_PRBS23[6]  = X[9]  ^ X[4]  ^ 1 ;
assign  Y_PRBS23[5]  = X[8]  ^ X[3]  ^ 1 ;
assign  Y_PRBS23[4]  = X[7]  ^ X[2]  ^ 1 ;
assign  Y_PRBS23[3]  = X[6]  ^ X[1]  ^ 1 ;
assign  Y_PRBS23[2]  = X[23] ^ X[18] ^ X[5] ^ 0 ;
assign  Y_PRBS23[1]  = X[22] ^ X[17] ^ X[4] ^ 0 ;

//PRBS-31: 1 + X28 + X31
assign  Y_PRBS31[20] = X[31] ^ X[28] ^ 1 ;
assign  Y_PRBS31[19] = X[30] ^ X[27] ^ 1 ;
assign  Y_PRBS31[18] = X[29] ^ X[26] ^ 1 ;
assign  Y_PRBS31[17] = X[28] ^ X[25] ^ 1 ;
assign  Y_PRBS31[16] = X[27] ^ X[24] ^ 1 ;
assign  Y_PRBS31[15] = X[26] ^ X[23] ^ 1 ;
assign  Y_PRBS31[14] = X[25] ^ X[22] ^ 1 ;
assign  Y_PRBS31[13] = X[24] ^ X[21] ^ 1 ;
assign  Y_PRBS31[12] = X[23] ^ X[20] ^ 1 ;
assign  Y_PRBS31[11] = X[22] ^ X[19] ^ 1 ;
assign  Y_PRBS31[10] = X[21] ^ X[18] ^ 1 ;
assign  Y_PRBS31[9]  = X[20] ^ X[17] ^ 1 ;
assign  Y_PRBS31[8]  = X[19] ^ X[16] ^ 1 ;
assign  Y_PRBS31[7]  = X[18] ^ X[15] ^ 1 ;
assign  Y_PRBS31[6]  = X[17] ^ X[14] ^ 1 ;
assign  Y_PRBS31[5]  = X[16] ^ X[13] ^ 1 ;
assign  Y_PRBS31[4]  = X[15] ^ X[12] ^ 1 ;
assign  Y_PRBS31[3]  = X[14] ^ X[11] ^ 1 ;
assign  Y_PRBS31[2]  = X[13] ^ X[10] ^ 1 ;
assign  Y_PRBS31[1]  = X[12] ^ X[9]  ^ 1 ;

assign  Y_20UI[20:1]  = {20{poll}}; //20UI squre wave

assign  Y_D10_2[20:1] = 20'b0101010101_0101010101;//D10.2 

assign  Y_LONG1[20:1] = {20{1'b1}};//long '1'

assign  Y_LONG0[20:1] = {20{1'b0}};//long '0'

//long pcie compliance pattern
assign  Y_PCIE[20:1]  = (poll == 1'b0) ? 20'b001111_1010_101010_1010 :
                                         20'b110000_0101_010101_0101;

always @(*) begin
   case (cfg_prbs_mode)
      1:       y_all = Y_PRBS7;
      2:       y_all = Y_PRBS15;
      3:       y_all = Y_PRBS23;
      4:       y_all = Y_PRBS31; 
      5:       y_all = Y_LONG1;
      6:       y_all = Y_LONG0;            
      7:       y_all = Y_20UI;
      8:       y_all = Y_D10_2;
      9:       y_all = Y_PCIE;
        
      default: y_all = 0;      
   endcase    
end
always @ (*) begin
   y_comb[32 :21] = X[12 : 1];
   
   if (PRBS_GEN_EN) begin
      y_comb[20:1]= y_all;
   end
   else
      y_comb[20:1] = {din[0],  din[1],  din[2],  din[3],  din[4],  din[5],  din[6],  din[7],  din[8],  din[9],
                      din[10], din[11], din[12], din[13], din[14], din[15], din[16], din[17], din[18], din[19]};
end

always @(posedge clk or negedge rstn)
   if (!rstn) begin
      latch_y         <= 32'd0;
      latch_y_all     <= 20'd0;
   end
   else if (clk_en == 1'b1)
   begin
      latch_y         <= y_comb; 
      latch_y_all     <= y_all;
   end

always @(posedge clk or negedge rstn)
   if (!rstn) begin
      error            <= 1'b0;
      error_cnt        <= 0;
      cfg_error_cnt_clr_d  <= 0;
   end
   else if(clk_en == 1'b1)
   begin
      error            <= latch_y_all != latch_y[20:1]; //for cfg_prbs_mode 1~6
      cfg_error_cnt_clr_d  <= {cfg_error_cnt_clr_d[0], cfg_error_cnt_clr};
      
      if (cfg_error_cnt_clr_d[1])
         error_cnt <= 0;
      else if (error_cnt != 8'hff)
         error_cnt <= error_cnt + error;
   end


always @(posedge clk or negedge rstn)
   if (!rstn) begin
      poll            <= 1'b0;
      cfg_insert_er_d <= 0;
   end
   else if(clk_en == 1'b1)
   begin
      poll            <= ~ poll;
      cfg_insert_er_d <= {cfg_insert_er_d[2:0], cfg_insert_er};
   end

assign X = latch_y;

assign dout[19:1]  = {X[1],  X[2],  X[3],  X[4],  X[5],  X[6],  X[7],  X[8],  X[9],  X[10],
                      X[11], X[12], X[13], X[14], X[15], X[16], X[17], X[18], X[19]};
                      
assign cfg_insert_er_p = cfg_insert_er_d[2] & (~ cfg_insert_er_d[3]);
 
assign dout[0] = cfg_insert_er_p ? ~X[20] : X[20];

endmodule


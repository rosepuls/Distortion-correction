//******************************************************************

//******************************************************************
`timescale 1ns/1ns
`define UD #1
module send_encode(

    input           tx_clk,
    input           rstn,    
    input           pix_clk,
    input           hs_in,
    input           vs_in,
    input           de_in/*synthesis PAP_MARK_DEBUG="1"*/,
    input  [15:0]   video_data_in/*synthesis PAP_MARK_DEBUG="1"*/,

    output reg[31:0]txd/*synthesis PAP_MARK_DEBUG="1"*/,
    output reg[ 3:0]txk/*synthesis PAP_MARK_DEBUG="1"*/
);
parameter H_ACT=16'd1280;
parameter IDLE=0;
parameter V_SYNC=1;//帧同步1
parameter H_START = 2;//帧同步2
parameter H_START1 = 1;//帧同步2
parameter H_DATA  = 3;//行开始
parameter H_END   = 4;//行数据

reg [15:0]cnt/*synthesis PAP_MARK_DEBUG="1"*/;
always@(posedge pix_clk)
begin
    if(de_in)
        cnt <= cnt +1'b1;
    else
        cnt <= 16'd0;

end
reg [10:0]rst_cnt=0;
always@(posedge tx_clk)
begin
    if(!rstn)
        rst_cnt <= 11'd0;
    else if(rst_cnt < 11'd50)
        rst_cnt <= rst_cnt + 11'd1;
    else
        rst_cnt <= rst_cnt;
end


reg vs_in_t1;
reg vs_in_t2;
reg vs_in_t3;
always@(posedge tx_clk)
begin
	vs_in_t1 <= vs_in;
	vs_in_t2 <= vs_in_t1;
	vs_in_t3 <= vs_in_t2;
end

reg vs_in_p1;
reg vs_in_p2;
reg vs_in_p3;
always@(posedge pix_clk)
begin
	vs_in_p1 <= vs_in;
	vs_in_p2 <= vs_in_p1;
	vs_in_p3 <= vs_in_p2;
end
reg [5:0]vs_cnt;
always@(posedge pix_clk)
begin
    if(!rstn)
        vs_cnt <= 6'd0;
    else if(vs_in_p2 & ~vs_in_p3 && vs_cnt <6'd3)
        vs_cnt <= vs_cnt + 1'd1;
    else
        vs_cnt <= vs_cnt;
end

wire video_frame_sync;
assign video_frame_sync = vs_in_t2 & ~vs_in_t3;       //判断ov5640视频图像的列同步信号vs的下降沿

wire[10:0] rd_water_level/*synthesis PAP_MARK_DEBUG="1"*/;
wire[31:0] rd_data;
reg rd_en=0;
reg rd_en_1d;
reg rd_en_2d;
reg [15:0]video_data;
always@(posedge pix_clk)
begin
    if(de_in)
        video_data <= video_data +1'b1;
    else
        video_data <= 16'd0;
        
end
reg valid;
always@(posedge pix_clk)
begin
    if(!rstn)
        valid <= 1'd0;
    else if(vs_in_p2 & ~vs_in_p3)
        valid <= 1'd1;
    else
        valid <= valid;
end

fifo_16_to_32 fifo_16_to_32(
    .wr_clk(pix_clk),
    .wr_rst(vs_in_p2 & ~vs_in_p3),//写复位，写指针归零
    .wr_en(de_in && valid),
    .wr_data(video_data_in),
    .wr_full(),
    .wr_water_level(),
    .almost_full(),
    .rd_clk(tx_clk),
    .rd_rst(vs_in_t2 & ~vs_in_t3),//读端口复位，读指针归零
    .rd_en(rd_en && valid),
    .rd_data(rd_data),
    .rd_empty(),
    .rd_water_level(rd_water_level),//读数据水位，fifo内可读数据数量
    .almost_empty());
    
reg[15:0] rd_cnt;
always@(posedge tx_clk )
begin
	if(!rstn)
		rd_cnt <= 16'd0;
	else if(rd_en)
		rd_cnt <= rd_cnt + 16'd1;
	else
		rd_cnt <= 16'd0;
end
reg[2:0] state=3'b0;
reg[2:0] state_n=3'b0;
always @(posedge tx_clk)
begin
    state <= state_n;
end

always @ (*)
begin
  case(state)
      IDLE       :  
      begin
          if(vs_in_t2 & ~vs_in_t3)                                     //监测到start信号到来，下一状态跳转到start状态
              state_n = V_SYNC;
          else if(rd_water_level >= H_ACT/2)
              state_n = H_START;
          else
              state_n = IDLE;
      end
      V_SYNC    :  
      begin
          if(rd_water_level >= H_ACT/2)                     //已完成接收start标志信号
              state_n = H_START;
          else
              state_n = IDLE;
      end
      H_START    :  
      begin
          state_n = H_DATA;
      end
      // H_START1    :  
      // begin
          // state_n = H_DATA;
      // end
      H_DATA    :  
      begin
          if(rd_cnt == H_ACT/2)                       //已完成接收stop标志信号
              state_n = H_END;
          else
              state_n = H_DATA;
      end
      H_END    :  
      begin                                         //没有其他状况出现时，回到空闲状态，等待start信号的到来
          state_n = IDLE;
      end
      default    :  state_n = IDLE;
  endcase
end

always@(posedge tx_clk)
begin
	if(!rstn)
		rd_en <= 1'b0;
    else if((state==V_SYNC ||state==IDLE) && rd_water_level >= H_ACT/2)
		rd_en <= 1'b1;
    else if(rd_cnt == H_ACT/2 - 1'b1)
		rd_en <= 1'b0;
    else
		rd_en <= rd_en;
end
always@(posedge tx_clk)
begin
    rd_en_1d <= rd_en;
    rd_en_2d <= rd_en_1d;
end
always@(posedge tx_clk)
begin
	if(!rstn)
    begin
        txd <= 32'h00_00_00_bc;
        txk <= 4'b0001;
    end
    else if(state == IDLE)
    begin
        txd <= 32'h00_00_00_bc;
        txk <= 4'b0001;
    end
    else if(state == V_SYNC)
    begin
        txd <= 32'hff_aa_aa_bc;
        txk <= 4'b0001;
    end
    else if(state == H_START)
    begin
        txd <= 32'haa_00_00_bc;
        txk <= 4'b0001;
    end
    
    else if(state == H_DATA)
    begin
        txd <= rd_data;
        txk <= 4'b0000;
    end
    
    else if(state == H_END)
    begin
        txd <= 32'hcc_00_00_bc;
        txk <= 4'b0001;
    end
    
    else
    begin
        txd <= 32'h00_00_00_bc;
        txk <= 4'b0001;
    end
    
end


endmodule 

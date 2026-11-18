module rec_decode(
	input           rstn,
	input           rx_clk,
    input           pix_clk,
	input   [31:0]  rxd/*synthesis PAP_MARK_DEBUG="1"*/,
	input   [3:0]   rxk/*synthesis PAP_MARK_DEBUG="1"*/,
	
    input           de_sync_vg/*synthesis PAP_MARK_DEBUG="1"*/,
    output          vs_sfp_rx,

	output  [15:0]  vout_data_o/*synthesis PAP_MARK_DEBUG="1"*/
    
);
parameter H_ACT=16'd1280;
parameter IDLE           = 0;
parameter READ_LINE      = 1;
reg vs_flag=0/*synthesis PAP_MARK_DEBUG="1"*/;
reg vs_flag_1d;
reg[15:0] vs_cnt=0;
reg[15:0] wr_cnt=0/*synthesis PAP_MARK_DEBUG="1"*/;
reg wr_en=0/*synthesis PAP_MARK_DEBUG="1"*/;
//恢复帧同步信号
always@(posedge rx_clk)
begin
	if(!rstn)
		vs_flag <= 1'b0;
    else if(rxk == 4'b0001 && rxd == 32'hff_aa_aa_bc )    
		vs_flag <= 1'b1;
	else if(vs_cnt > 16'd200)
		vs_flag <= 1'b0;
    else
        vs_flag <= vs_flag;
end
always@(posedge rx_clk)
begin
    if(!rstn)
        vs_cnt <= 16'd0;
    else if(vs_flag)
        vs_cnt <= vs_cnt + 16'd1;
    else
        vs_cnt <= 16'd0;
end
assign vs_sfp_rx=vs_flag;//? : ;
reg vs_rstn;
always@(posedge rx_clk)
begin
    if(!rstn)
        vs_rstn <= 1'd0;
    else if(vs_flag)
        vs_rstn <= 1'd1;
    else
        vs_rstn <= 1'd1;
end
always@(posedge rx_clk)
begin
	if(!rstn)
		wr_en <= 1'b0;
	else if(rxk == 4'b0001 && rxd == 32'haa_00_00_bc)
		wr_en <= 1'b1;
	else if(wr_cnt == (H_ACT/2 - 16'd1))///写vout_width/2数量32bit数据，对应读vout_width数量的16bit数据
		wr_en <= 1'b0;
end
always@(posedge rx_clk)
begin
	if(!rstn)
		wr_cnt <= 16'd0;
	else if(wr_en)
		wr_cnt <= wr_cnt + 16'd1;
	else
		wr_cnt <= 16'd0;
end

wire[15:0] rd_data_count/*synthesis PAP_MARK_DEBUG="1"*/;

wire full/*synthesis PAP_MARK_DEBUG="1"*/;
wire empty/*synthesis PAP_MARK_DEBUG="1"*/;
wire [15:0]vout_data;
fifo_32_to_16 fifo_32_to_16(     
    .wr_clk(rx_clk),
    .wr_rst(vs_flag || !rstn),
    .wr_en(wr_en),
    .wr_data(rxd),
    .wr_full(full),
    .wr_water_level(),

    .almost_full(),
    .rd_clk(pix_clk),
    .rd_rst(vs_flag || !rstn),
    .rd_en(de_sync_vg),
    .rd_data(vout_data),
    .rd_empty(empty),
    .rd_water_level(rd_data_count),
    .almost_empty());
reg de_sync_vg_1d;
always@(posedge pix_clk)
begin
    de_sync_vg_1d<=de_sync_vg;
end
assign vout_data_o=(de_sync_vg_1d)? vout_data:16'h5555;

endmodule 
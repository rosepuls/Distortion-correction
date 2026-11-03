`timescale 1ns/1ps
// One active sample window, one ordered mode lookahead, and one kernel
// result in flight. Fetching the next window can overlap the previous kernel.
// Reuse inherited Tile Cache in 2x2 probes: 1/4/9 probes for 2/4/5 support.
module adaptive_sampler #(
 parameter integer IMAGE_WIDTH=1280,IMAGE_HEIGHT=720,CACHE_SET_COUNT=16,CACHE_WAYS=4
)(
 input wire clk,rstn,source_frame_start,input wire [1:0] source_frame_slot,
 input wire s_valid,output wire s_ready,
 input wire signed [31:0] s_sx,s_sy,s_j00,s_j01,s_j10,s_j11,
 input wire s_j_valid,s_geometry_valid,
 input wire [19:0] s_pixel_id,input wire [31:0] s_frame_id,
 input wire [15:0] s_param_version,input wire s_sof,s_eol,s_eof,
 output wire m_valid,input wire m_ready,output wire [31:0] m_pixel,
 output wire m_geometry_valid,output reg [19:0] m_pixel_id,
 output reg [31:0] m_frame_id,output reg [15:0] m_param_version,
 output reg m_sof,m_eol,m_eof,
 output wire read_valid,output wire [27:0] read_addr,output wire [3:0] read_len,
 output wire read_reserve,input wire read_ready,read_rvalid,
 input wire [255:0] read_rdata,input wire read_rlast,
 output wire reader_idle,reader_fault,output wire [15:0] read_error_count,
 output wire [31:0] fetched_rows,output wire [23:0] diagnostic_miss_count,diagnostic_fill_cycles,
 output wire read_response_wait,first_beat_wait,interbeat_wait
);
 localparam IDLE=0,PLAN=1,REQ=2,RSP=3,SEND=4,WAIT_RESULT=5,BLACK=6,CLASSIFY=7;
 reg [2:0] state;
 reg signed [31:0] sx,sy,j00,j01,j10,j11;
 reg jvalid,geometry;
 reg [19:0] current_pixel_id;
 reg [31:0] current_frame_id;
 reg [15:0] current_param_version;
 reg current_sof,current_eol,current_eof;
 reg out_busy,out_black,out_geometry;
 reg [1:0] out_mode;
 wire [1:0] selector_mode;
 reg [1:0] selected_mode;
 reg [1:0] mode;
 reg [2:0] size,col,row;
 reg [10:0] base_x;reg [9:0] base_y;
 reg [15:0] fx,fy;
 reg [799:0] samples;
 // Reuse only a complete previous window with matching frame, version, mode
 // and row. The source-frame invalidation also invalidates this register file.
 reg window_valid,right_column_only;
 reg [10:0] window_x;
 reg [9:0] window_y;
 reg [2:0] window_size;
 reg [1:0] window_mode;
 reg [31:0] window_frame;
 reg [15:0] window_version;
 reg [31:0] same_window_count,shift_window_count;
 integer wr,wc;
 reg frame_fault;
 reg [31:0] bilinear_count /* synthesis PAP_MARK_DEBUG="true" */;
 reg [31:0] bicubic_count /* synthesis PAP_MARK_DEBUG="true" */;
 reg [31:0] ewa_count /* synthesis PAP_MARK_DEBUG="true" */;
 reg [31:0] black_count /* synthesis PAP_MARK_DEBUG="true" */;
 reg [31:0] clipped_count /* synthesis PAP_MARK_DEBUG="true" */;
 reg pending;
 reg signed [31:0] pending_sx,pending_sy,pending_j00,pending_j01,pending_j10,pending_j11;
 reg pending_jvalid,pending_geometry;
 reg [19:0] pending_pixel_id;
 reg [31:0] pending_frame_id;
 reg [15:0] pending_param_version;
 reg pending_sof,pending_eol,pending_eof;
 wire selector_clipped,selector_ready,selector_valid;
 reg clipped;
 wire selector_take=selector_valid&&pending&&state==IDLE&&!source_frame_start&&!reader_fault;
 adaptive_mode_selector selector(.clk(clk),.rstn(rstn),
  .s_valid(s_valid&&!pending&&!source_frame_start&&!reader_fault),.s_ready(selector_ready),
  .j00(s_j00),.j01(s_j01),.j10(s_j10),.j11(s_j11),.j_valid(s_j_valid),.geometry_valid(s_geometry_valid),
  .m_valid(selector_valid),.m_ready(selector_take),.mode(selector_mode),.clipped(selector_clipped));
 wire signed [31:0] ix=sx>>>16,iy=sy>>>16;
 wire small_ok=geometry&&ix>=0&&iy>=0&&ix<IMAGE_WIDTH-1&&iy<IMAGE_HEIGHT-1;
 wire large_ok=ix>=(selected_mode==2?2:1)&&iy>=(selected_mode==2?2:1)&&ix<IMAGE_WIDTH-2&&iy<IMAGE_HEIGHT-2;
 wire [1:0] final_mode=(selected_mode!=0&&!large_ok)?2'd0:selected_mode;
 wire [10:0] desired_x=ix-(final_mode==2?2:final_mode==1?1:0);
 wire [9:0] desired_y=iy-(final_mode==2?2:final_mode==1?1:0);
 wire window_match=window_valid&&window_mode==final_mode&&window_frame==current_frame_id&&window_version==current_param_version&&window_y==desired_y;
 wire cache_ready,cache_valid,cache_idle,cache_fault;
 wire [31:0] p00,p10,p01,p11;
 wire [10:0] x0=base_x+col;
 wire [9:0] y0=base_y+row;
 wire [10:0] x1=(col+1<size)?x0+11'd1:x0;
 wire [9:0] y1=(row+1<size)?y0+10'd1:y0;
 wire br,cr,er,bv,cv,ev;
 wire [31:0] bp,cp,ep;
 wire kernel_ready=mode==0?br:mode==1?cr:er;
 wire output_kernel_valid=out_mode==0?bv:out_mode==1?cv:ev;
 wire output_fire=m_valid&&m_ready;
 wire issue_slot=!out_busy||output_fire;
 assign s_ready=rstn&&!pending&&!source_frame_start&&!reader_fault&&selector_ready;
 assign m_valid=out_busy&&(out_black||output_kernel_valid);
 assign m_pixel=out_black?32'd0:out_mode==0?bp:out_mode==1?cp:ep;
 assign m_geometry_valid=out_busy&&!out_black&&out_geometry;
 assign reader_idle=state==IDLE&&cache_idle&&!pending&&!selector_valid&&!out_busy;
 assign reader_fault=cache_fault||frame_fault;
 cached_neighbor_reader #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),.SET_COUNT(CACHE_SET_COUNT),.WAYS(CACHE_WAYS)) reader(
  .clk(clk),.rstn(rstn),.source_frame_start(source_frame_start),.source_frame_slot(source_frame_slot),
  .s_valid(state==REQ),.s_ready(cache_ready),.s_x0(x0),.s_x1(x1),.s_y0(y0),.s_y1(y1),
  .s_fx(16'd0),.s_fy(16'd0),.s_neighbor_valid(4'hf),.s_geometry_valid(1'b1),
  .s_pixel_id(current_pixel_id),.s_frame_id(current_frame_id),.s_param_version(current_param_version),.s_sof(current_sof),.s_eol(current_eol),.s_eof(current_eof),
  .m_valid(cache_valid),.m_ready(state==RSP),.m_p00(p00),.m_p10(p10),.m_p01(p01),.m_p11(p11),
  .read_valid(read_valid),.read_addr(read_addr),.read_len(read_len),.read_reserve(read_reserve),
  .read_ready(read_ready),.read_rvalid(read_rvalid),.read_rdata(read_rdata),.read_rlast(read_rlast),
  .idle(cache_idle),.fatal_fault(cache_fault),.read_error_count(read_error_count),.fetched_rows(fetched_rows),
  .diagnostic_miss_count(diagnostic_miss_count),.diagnostic_fill_cycles(diagnostic_fill_cycles),
  .read_response_wait(read_response_wait),.first_beat_wait(first_beat_wait),.interbeat_wait(interbeat_wait)
 );
 pipelined_bilinear_interpolator bilinear(
  .clk(clk),.rstn(rstn),.s_valid(state==SEND&&issue_slot&&mode==0),.s_ready(br),
  .s_p00(samples[31:0]),.s_p10(samples[63:32]),.s_p01(samples[95:64]),.s_p11(samples[127:96]),
  .s_fx(fx),.s_fy(fy),.s_neighbor_valid(4'hf),.s_geometry_valid(geometry),
  .s_pixel_id(current_pixel_id),.s_frame_id(current_frame_id),.s_param_version(current_param_version),.s_sof(current_sof),.s_eol(current_eol),.s_eof(current_eof),
  .m_valid(bv),.m_ready(out_busy&&!out_black&&out_mode==0&&m_ready),.m_pixel(bp)
 );
 pipelined_catmull_rom_interpolator bicubic(
  .clk(clk),.rstn(rstn),.s_valid(state==SEND&&issue_slot&&mode==1),.s_ready(cr),.s_samples(samples[511:0]),
  .s_fx(fx),.s_fy(fy),.s_neighbor_valid(16'hffff),.s_geometry_valid(geometry),
  .s_pixel_id(current_pixel_id),.s_frame_id(current_frame_id),.s_param_version(current_param_version),.s_sof(current_sof),.s_eol(current_eol),.s_eof(current_eof),
  .m_valid(cv),.m_ready(out_busy&&!out_black&&out_mode==1&&m_ready),.m_pixel(cp)
 );
 bounded_ewa_interpolator ewa(
  .clk(clk),.rstn(rstn),.s_valid(state==SEND&&issue_slot&&mode==2),.s_ready(er),.s_samples(samples),.s_fx(fx),.s_fy(fy),
  .s_j00(j00),.s_j01(j01),.s_j10(j10),.s_j11(j11),.m_valid(ev),.m_ready(out_busy&&!out_black&&out_mode==2&&m_ready),.m_pixel(ep)
 );
 always @(posedge clk) begin
  if(!rstn) begin state<=IDLE;pending<=0;out_busy<=0;out_black<=0;frame_fault<=0;bilinear_count<=0;bicubic_count<=0;ewa_count<=0;black_count<=0;clipped_count<=0;window_valid<=0;right_column_only<=0;same_window_count<=0;shift_window_count<=0;end
  else begin
   if(output_fire) out_busy<=0;
   if(s_valid&&s_ready) begin
    pending<=1;
    pending_sx<=s_sx;pending_sy<=s_sy;pending_j00<=s_j00;pending_j01<=s_j01;pending_j10<=s_j10;pending_j11<=s_j11;
    pending_jvalid<=s_j_valid;pending_geometry<=s_geometry_valid;
    {pending_pixel_id,pending_frame_id,pending_param_version,pending_sof,pending_eol,pending_eof}<=
     {s_pixel_id,s_frame_id,s_param_version,s_sof,s_eol,s_eof};
   end
   if(selector_take) pending<=0;
   if(source_frame_start) begin
    if(!reader_idle) frame_fault<=1;
    window_valid<=0;same_window_count<=0;shift_window_count<=0;
    bilinear_count<=0;bicubic_count<=0;ewa_count<=0;black_count<=0;clipped_count<=0;
   end
   case(state)
    IDLE: if(selector_take) begin
     sx<=pending_sx;sy<=pending_sy;j00<=pending_j00;j01<=pending_j01;j10<=pending_j10;j11<=pending_j11;
     jvalid<=pending_jvalid;geometry<=pending_geometry;selected_mode<=selector_mode;clipped<=selector_clipped;
     fx<=pending_sx[15:0];fy<=pending_sy[15:0];
     {current_pixel_id,current_frame_id,current_param_version,current_sof,current_eol,current_eof}<=
      {pending_pixel_id,pending_frame_id,pending_param_version,pending_sof,pending_eol,pending_eof};state<=CLASSIFY;
    end
    CLASSIFY: begin
     mode<=final_mode;col<=0;row<=0;
     if(!small_ok) begin state<=BLACK;black_count<=black_count+1'b1;window_valid<=0;end
     else begin
      case(final_mode)
       0:begin size<=2;base_x<=ix;base_y<=iy;bilinear_count<=bilinear_count+1'b1;end
       1:begin size<=4;base_x<=ix-1;base_y<=iy-1;bicubic_count<=bicubic_count+1'b1;end
       2:begin size<=5;base_x<=ix-2;base_y<=iy-2;ewa_count<=ewa_count+1'b1;if(clipped) clipped_count<=clipped_count+1'b1;end
       default:begin size<=2;base_x<=ix;base_y<=iy;end
      endcase
      right_column_only<=0;
      if(window_match&&desired_x==window_x) begin
       same_window_count<=same_window_count+1'b1;state<=SEND;
      end else if(window_match&&desired_x==window_x+1'b1) begin
       for(wr=0;wr<5;wr=wr+1) for(wc=0;wc<4;wc=wc+1)
        if(wr<window_size&&wc<window_size-1)
         samples[(wr*window_size+wc)*32+:32]<=samples[(wr*window_size+wc+1)*32+:32];
       col<=window_size-1'b1;right_column_only<=1;
       shift_window_count<=shift_window_count+1'b1;state<=REQ;
      end else state<=REQ;
     end
    end
    REQ:if(cache_ready) state<=RSP;
    RSP:if(cache_valid) begin
     samples[(row*size+col)*32+:32]<=p00;
     if(col+1<size) samples[(row*size+col+1)*32+:32]<=p10;
     if(row+1<size) samples[((row+1)*size+col)*32+:32]<=p01;
     if(col+1<size&&row+1<size) samples[((row+1)*size+col+1)*32+:32]<=p11;
     if(col+2>=size) begin
      col<=right_column_only?size-1'b1:0;
      if(row+2>=size) state<=SEND;
      else begin row<=row+2;state<=REQ;end
     end else begin col<=col+2;state<=REQ;end
    end
    SEND:if(issue_slot&&kernel_ready) begin
     out_busy<=1;out_black<=0;out_geometry<=geometry;out_mode<=mode;
     {m_pixel_id,m_frame_id,m_param_version,m_sof,m_eol,m_eof}<=
      {current_pixel_id,current_frame_id,current_param_version,current_sof,current_eol,current_eof};
     window_valid<=1;window_x<=base_x;window_y<=base_y;window_size<=size;window_mode<=mode;window_frame<=current_frame_id;window_version<=current_param_version;
     state<=IDLE;
    end
    BLACK:if(issue_slot) begin
     out_busy<=1;out_black<=1;out_geometry<=0;out_mode<=0;
     {m_pixel_id,m_frame_id,m_param_version,m_sof,m_eol,m_eof}<=
      {current_pixel_id,current_frame_id,current_param_version,current_sof,current_eol,current_eof};
     state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule

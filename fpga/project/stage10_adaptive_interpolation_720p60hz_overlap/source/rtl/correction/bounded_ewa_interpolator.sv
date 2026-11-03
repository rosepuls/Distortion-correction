`timescale 1ns/1ps
// Fixed-point bounded EWA. One coordinate at a time; its 25 samples move
// through a one-sample-per-cycle arithmetic and restoring-division pipeline.
// Numerical contract is identical to the Stage 10 functional baseline.
module bounded_ewa_interpolator(
 input wire clk,rstn,s_valid,output wire s_ready,
 input wire [799:0] s_samples,input wire [15:0] s_fx,s_fy,
 input wire signed [31:0] s_j00,s_j01,s_j10,s_j11,
 output wire m_valid,input wire m_ready,output reg [31:0] m_pixel
);
 localparam IDLE=0,NORM=1,COV=2,DET=3,RUN=4,DIVINIT=5,DIV=6,OUT=7;
 reg [2:0] state;
 reg [799:0] samples;
 reg [7:0] fx,fy;
 reg signed [31:0] j0,j1,j2,j3;
 wire signed [11:0] q0=j0>>>8,q1=j1>>>8,q2=j2>>>8,q3=j3>>>8;
 reg signed [24:0] a,b,c;
 reg [49:0] determinant;
 reg [4:0] launch_index;
 reg [2:0] col,row;
 reg signed [11:0] dx0,dy0;
 reg signed [23:0] dx2,dy2,dxy;
 reg signed [48:0] nx,ny,nxy;
 reg signed [63:0] numerator;
 reg [63:0] rem_pipe [0:6];
 reg [5:0] idx_pipe [0:6];
 reg outside_pipe [0:6];
 reg [31:0] pixel_pipe [0:12];
 reg [12:0] weights [0:63];
 reg [12:0] weight_reg,weight_reg_delay;
 reg [20:0] prod_r,prod_g,prod_b;
 reg [16:0] weight_sum;
 reg [25:0] ar,ag,ab,rr,rg,rb;
 reg [7:0] qr,qg,qb;
 reg [3:0] bit_index;
 reg [12:0] valid_pipe,last_pipe;
 wire [25:0] divisor={9'd0,weight_sum}<<bit_index;
 integer i;
 initial $readmemh("source/rtl/correction/ewa_weights_q12.mem",weights);
 assign s_ready=rstn&&state==IDLE;
 assign m_valid=state==OUT;
 always @(posedge clk) begin
  if(!rstn) begin
   state<=IDLE;m_pixel<=0;valid_pipe<=0;last_pipe<=0;
  end else begin
   if(state==RUN) begin
    valid_pipe<={valid_pipe[11:0],(launch_index<25)};
    last_pipe<={last_pipe[11:0],(launch_index==24)};
    if(launch_index<25) begin
     dx0<=($signed({1'b0,col})-12'sd2)*12'sd256-$signed({1'b0,fx});
     dy0<=($signed({1'b0,row})-12'sd2)*12'sd256-$signed({1'b0,fy});
     pixel_pipe[0]<=samples[launch_index*32+:32];
     launch_index<=launch_index+1'b1;
     if(col==4) begin col<=0;row<=row+1'b1;end else col<=col+1'b1;
    end
    for(i=1;i<13;i=i+1) pixel_pipe[i]<=pixel_pipe[i-1];
    if(valid_pipe[0]) begin dx2<=dx0*dx0;dy2<=dy0*dy0;dxy<=dx0*dy0;end
    if(valid_pipe[1]) begin nx<=c*dx2;ny<=a*dy2;nxy<=b*dxy;end
    if(valid_pipe[2]) numerator<=(nx-2*nxy+ny)*64'sd16;
    if(valid_pipe[3]) begin
     rem_pipe[0]<=numerator;
     outside_pipe[0]<=numerator>=({14'd0,determinant}<<6);
     idx_pipe[0]<=0;
    end
    for(i=1;i<=6;i=i+1) begin
     if(valid_pipe[i+3]) begin
      outside_pipe[i]<=outside_pipe[i-1];
      if(!outside_pipe[i-1] && rem_pipe[i-1]>=({14'd0,determinant}<<(6-i))) begin
       rem_pipe[i]<=rem_pipe[i-1]-({14'd0,determinant}<<(6-i));
       idx_pipe[i]<=idx_pipe[i-1] | (6'd1<<(6-i));
      end else begin rem_pipe[i]<=rem_pipe[i-1];idx_pipe[i]<=idx_pipe[i-1];end
     end
    end
    if(valid_pipe[10]) weight_reg<=outside_pipe[6]?0:weights[idx_pipe[6]];
    if(valid_pipe[11]) begin
     prod_r<=pixel_pipe[11][31:24]*weight_reg;
     prod_g<=pixel_pipe[11][23:16]*weight_reg;
     prod_b<=pixel_pipe[11][15:8]*weight_reg;
    end
    if(valid_pipe[12]) begin
     weight_sum<=weight_sum+weight_reg_delay;
     ar<=ar+prod_r;ag<=ag+prod_g;ab<=ab+prod_b;
     if(last_pipe[12]) state<=DIVINIT;
    end
    if(valid_pipe[11]) weight_reg_delay<=weight_reg;
   end
   case(state)
    IDLE: if(s_valid) begin
     samples<=s_samples;fx<=s_fx[15:8];fy<=s_fy[15:8];
     j0<=s_j00;j1<=s_j01;j2<=s_j10;j3<=s_j11;
     weight_sum<=0;ar<=0;ag<=0;ab<=0;launch_index<=0;row<=0;col<=0;
     valid_pipe<=0;last_pipe<=0;state<=NORM;
    end
    NORM: if(j0>262144||j0< -262144||j1>262144||j1< -262144||j2>262144||j2< -262144||j3>262144||j3< -262144) begin
     j0<=j0>>>1;j1<=j1>>>1;j2<=j2>>>1;j3<=j3>>>1;
    end else state<=COV;
    COV: begin a<=q0*q0+q1*q1+25'sd65536;b<=q0*q2+q1*q3;c<=q2*q2+q3*q3+25'sd65536;state<=DET;end
    DET: begin determinant<=a*c-b*b;state<=RUN;end
    RUN: begin end
    DIVINIT: if(weight_sum==0) begin m_pixel<={samples[415:392],8'd0};state<=OUT;end
     else begin rr<=ar+(weight_sum>>1);rg<=ag+(weight_sum>>1);rb<=ab+(weight_sum>>1);qr<=0;qg<=0;qb<=0;bit_index<=7;state<=DIV;end
    DIV: begin
     if(rr>=divisor) begin rr<=rr-divisor;qr[bit_index]<=1;end
     if(rg>=divisor) begin rg<=rg-divisor;qg[bit_index]<=1;end
     if(rb>=divisor) begin rb<=rb-divisor;qb[bit_index]<=1;end
     if(bit_index==0) begin
      m_pixel<={qr[7:1],rr>=divisor,qg[7:1],rg>=divisor,qb[7:1],rb>=divisor,8'd0};state<=OUT;
     end else bit_index<=bit_index-1'b1;
    end
    OUT: if(m_ready) state<=IDLE;
    default:state<=IDLE;
   endcase
  end
 end
endmodule

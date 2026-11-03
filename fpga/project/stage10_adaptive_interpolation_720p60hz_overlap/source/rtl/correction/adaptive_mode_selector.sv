`timescale 1ns/1ps
// Elastic arithmetic stages for exact singular-value thresholds. All outputs
// remain stable under backpressure. Component guards bound multiplier widths.
module adaptive_mode_selector(
 input wire clk,rstn,s_valid,output wire s_ready,
 input wire signed [31:0] j00,j01,j10,j11,
 input wire j_valid,geometry_valid,
 output reg m_valid,input wire m_ready,output reg [1:0] mode,output reg clipped
);
 wire advance=rstn&&(!m_valid||m_ready);
 assign s_ready=advance;
 reg [4:0] valid_pipe;
 reg [2:0] flags[0:4];
 wire big_mode=j00>=81920||j00<=-81920||j01>=81920||j01<=-81920||j10>=81920||j10<=-81920||j11>=81920||j11<=-81920;
 wire big_clip=j00>131072||j00< -131072||j01>131072||j01< -131072||j10>131072||j10< -131072||j11>131072||j11< -131072;
 wire signed [18:0] q0=big_clip?19'sd0:j00[18:0],q1=big_clip?19'sd0:j01[18:0],q2=big_clip?19'sd0:j10[18:0],q3=big_clip?19'sd0:j11[18:0];
 reg signed [18:0] q0r,q1r,q2r,q3r;
 reg signed [37:0] p0,p1,p2,p3,p4,p5,p6,p7;
 reg signed [38:0] a,b,c,detj;
 reg signed [39:0] da,dc,ka,kc;
 reg signed [47:0] ea,ec,eb;
 reg signed [38:0] b2;
 reg [2:0] sign_flags;
 reg [5:0] guard_flags;
 reg signed [79:0] le,re,lk;
 reg signed [95:0] lc,rc;
 always @(posedge clk) begin
  if(!rstn) begin valid_pipe<=0;m_valid<=0;mode<=0;clipped<=0;end
  else if(advance) begin
   valid_pipe<={valid_pipe[3:0],s_valid};
   m_valid<=valid_pipe[4];
   if(s_valid) begin
    flags[0]<={j_valid&&geometry_valid,big_mode,big_clip};
    q0r<=q0;q1r<=q1;q2r<=q2;q3r<=q3;
   end
   if(valid_pipe[0]) begin
    flags[1]<=flags[0];
    p0<=q0r*q0r;p1<=q1r*q1r;p2<=q2r*q2r;p3<=q3r*q3r;p4<=q0r*q2r;p5<=q1r*q3r;p6<=q0r*q3r;p7<=q1r*q2r;
   end
   if(valid_pipe[1]) begin
    flags[2]<=flags[1];a<=p0+p1;c<=p2+p3;b<=p4+p5;detj<=p6-p7;
   end
   if(valid_pipe[2]) begin
    flags[3]<=flags[2];
    da<=40'sd6710886400-a;dc<=40'sd6710886400-c;
    ka<=40'sd17179869184-a;kc<=40'sd17179869184-c;
    ea<=48'sd1241245548544-a*48'sd400;ec<=48'sd1241245548544-c*48'sd400;eb<=b*48'sd400;
    b2<=b;sign_flags<={detj!=0,a>39'sd17179869184||c>39'sd17179869184,a>=39'sd6710886400||c>=39'sd6710886400};
   end
   if(valid_pipe[3]) begin
    flags[4]<=flags[3];le<=da*dc;re<=b2*b2;lk<=ka*kc;lc<=ea*ec;rc<=eb*eb;
    guard_flags<={sign_flags,ea>=0,ec>=0,1'b0};
   end
   if(valid_pipe[4]) begin
    mode<=!flags[4][2]?0:(flags[4][1]||guard_flags[3]||le<=re)?2:
      (guard_flags[5]&&guard_flags[2]&&guard_flags[1]&&lc>=rc)?1:0;
    clipped<=flags[4][2]&&(flags[4][0]||guard_flags[4]||lk<re);
   end
  end
 end
endmodule

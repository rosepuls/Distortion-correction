// 1-pixel/clock narrowed Brown-Conrady mapper.
// Selected internal format: centered S23.Q12, inverse S26.Q24,
// normalized/coefficient/r2 S20.Q18, radial/distorted S21.Q18, focal S24.Q12.
module distortion_core_optimized #(
 parameter integer IMAGE_WIDTH=1280, IMAGE_HEIGHT=720, COORD_WIDTH=13
) (
 input wire clk,rst_n,input wire [COORD_WIDTH-1:0] in_u,in_v,input wire in_valid,in_sof,in_eol,
 input wire signed [31:0] cfg_fx_q19,cfg_fy_q19,cfg_cx_q19,cfg_cy_q19,cfg_inv_fx_q30,cfg_inv_fy_q30,cfg_k1_q28,cfg_k2_q28,cfg_p1_q28,cfg_p2_q28,
 output reg signed [63:0] out_src_x_q19,out_src_y_q19, output reg signed [31:0] out_x0,out_y0,
 output reg [15:0] out_dx_q16,out_dy_q16, output reg out_coord_valid,out_valid,out_sof,out_eol
);
 reg signed [31:0] ffx,ffy,fcx,fcy,ifix,ifiy,fk1,fk2,fp1,fp2;
 reg s1v,s1s,s1e,s2v,s2s,s2e,s3v,s3s,s3e,s4v,s4s,s4e;
 reg signed [19:0] s1x,s1y,s1k1,s1k2,s1p1,s1p2; reg signed [23:0] s1fx,s1fy,s1cx,s1cy;
 reg signed [19:0] s2r2,s2x2,s2y2,s2xy,s2x,s2y,s2k1,s2k2,s2p1,s2p2; reg signed [23:0] s2fx,s2fy,s2cx,s2cy;
 reg signed [19:0] s3x,s3y,s3r2,s3x2,s3y2,s3xy,s3p1,s3p2; reg signed [20:0] s3r,s3t; reg signed [23:0] s3fx,s3fy,s3cx,s3cy;
 reg signed [20:0] s4x,s4y; reg signed [23:0] s4fx,s4fy,s4cx,s4cy;
 wire signed [31:0] ax=(in_valid&&in_sof)?cfg_fx_q19:ffx, ay=(in_valid&&in_sof)?cfg_fy_q19:ffy;
 wire signed [31:0] acx=(in_valid&&in_sof)?cfg_cx_q19:fcx, acy=(in_valid&&in_sof)?cfg_cy_q19:fcy;
 wire signed [31:0] aix=(in_valid&&in_sof)?cfg_inv_fx_q30:ifix, aiy=(in_valid&&in_sof)?cfg_inv_fy_q30:ifiy;
 wire signed [31:0] ak1=(in_valid&&in_sof)?cfg_k1_q28:fk1, ak2=(in_valid&&in_sof)?cfg_k2_q28:fk2, ap1=(in_valid&&in_sof)?cfg_p1_q28:fp1, ap2=(in_valid&&in_sof)?cfg_p2_q28:fp2;
 wire signed [63:0] ux=($signed({1'b0,in_u})<<<19)-acx, uy=($signed({1'b0,in_v})<<<19)-acy;
 wire signed [22:0] cxx=ux>>>7, cyy=uy>>>7; wire signed [25:0] ixx=aix>>>6, iyy=aiy>>>6;
 wire signed [51:0] nxx=cxx*ixx, nyy=cyy*iyy;
 wire signed [55:0] x2=s1x*s1x, y2=s1y*s1y, xy=s1x*s1y;
 wire signed [39:0] k2r=s2k2*s2r2; wire signed [20:0] tcalc=s2k1+(k2r>>>18);
 wire signed [40:0] rprod=s2r2*tcalc; wire signed [20:0] rcalc=(21'sd262144)+(rprod>>>18);
 wire signed [55:0] rx=s3x*s3r, ry=s3y*s3r;
 wire signed [55:0] p1xy=s3p1*s3xy, p2xy=s3p2*s3xy, p2base=s3p2*(s3r2+(s3x2<<<1)), p1base=s3p1*(s3r2+(s3y2<<<1));
 wire signed [20:0] dxcalc=(rx>>>18)+(p1xy>>>17)+(p2base>>>18), dycalc=(ry>>>18)+(p1base>>>18)+(p2xy>>>17);
 wire signed [52:0] sxprod=s4fx*s4x, syprod=s4fy*s4y;
 wire signed [63:0] sxq=(sxprod>>>11)+($signed(s4cx)<<<7), syq=(syprod>>>11)+($signed(s4cy)<<<7);
 wire signed [31:0] spx,spy; wire [15:0] sdx,sdy; wire spv;
 coordinate_split #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT)) split(.src_x_q19(sxq),.src_y_q19(syq),.x0(spx),.y0(spy),.dx_q16(sdx),.dy_q16(sdy),.coord_valid(spv));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin ffx<=0;ffy<=0;fcx<=0;fcy<=0;ifix<=0;ifiy<=0;fk1<=0;fk2<=0;fp1<=0;fp2<=0; s1v<=0;s2v<=0;s3v<=0;s4v<=0;out_valid<=0;out_sof<=0;out_eol<=0;out_coord_valid<=0;out_src_x_q19<=0;out_src_y_q19<=0;out_x0<=0;out_y0<=0;out_dx_q16<=0;out_dy_q16<=0; end else begin
   out_valid<=s4v;out_sof<=s4v&&s4s;out_eol<=s4v&&s4e; if(s4v) begin out_src_x_q19<=sxq;out_src_y_q19<=syq;out_x0<=spx;out_y0<=spy;out_dx_q16<=sdx;out_dy_q16<=sdy;out_coord_valid<=spv;end else begin out_src_x_q19<=0;out_src_y_q19<=0;out_x0<=0;out_y0<=0;out_dx_q16<=0;out_dy_q16<=0;out_coord_valid<=0;end
   s4v<=s3v;s4s<=s3s;s4e<=s3e;s4x<=dxcalc;s4y<=dycalc;s4fx<=s3fx;s4fy<=s3fy;s4cx<=s3cx;s4cy<=s3cy;
   s3v<=s2v;s3s<=s2s;s3e<=s2e;s3x<=s2x;s3y<=s2y;s3r2<=s2r2;s3x2<=s2x2;s3y2<=s2y2;s3xy<=s2xy;s3t<=tcalc;s3r<=rcalc;s3p1<=s2p1;s3p2<=s2p2;s3fx<=s2fx;s3fy<=s2fy;s3cx<=s2cx;s3cy<=s2cy;
   s2v<=s1v;s2s<=s1s;s2e<=s1e;s2x<=s1x;s2y<=s1y;s2x2<=x2>>>18;s2y2<=y2>>>18;s2xy<=xy>>>18;s2r2<=(x2>>>18)+(y2>>>18);s2k1<=s1k1;s2k2<=s1k2;s2p1<=s1p1;s2p2<=s1p2;s2fx<=s1fx;s2fy<=s1fy;s2cx<=s1cx;s2cy<=s1cy;
   s1v<=in_valid;s1s<=in_valid&&in_sof;s1e<=in_valid&&in_eol;s1x<=nxx>>>18;s1y<=nyy>>>18;s1k1<=ak1>>>10;s1k2<=ak2>>>10;s1p1<=ap1>>>10;s1p2<=ap2>>>10;s1fx<=ax>>>7;s1fy<=ay>>>7;s1cx<=acx>>>7;s1cy<=acy>>>7;
   if(in_valid&&in_sof) begin ffx<=cfg_fx_q19;ffy<=cfg_fy_q19;fcx<=cfg_cx_q19;fcy<=cfg_cy_q19;ifix<=cfg_inv_fx_q30;ifiy<=cfg_inv_fy_q30;fk1<=cfg_k1_q28;fk2<=cfg_k2_q28;fp1<=cfg_p1_q28;fp2<=cfg_p2_q28;end
  end
 end
endmodule

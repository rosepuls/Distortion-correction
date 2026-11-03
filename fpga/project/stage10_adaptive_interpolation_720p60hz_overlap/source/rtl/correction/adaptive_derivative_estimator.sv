`timescale 1ns/1ps
// Raster history advances only on an accepted mapped coordinate. Per-entry
// frame/version/id tags reject stale lines, including after a partial frame.
module adaptive_derivative_estimator #(parameter integer IMAGE_WIDTH=1280)(
 input wire clk,rstn,s_valid, output wire s_ready,
 input wire signed [31:0] s_sx,s_sy,
 input wire s_geometry_valid,
 input wire [19:0] s_pixel_id, input wire [31:0] s_frame_id,
 input wire [15:0] s_param_version, input wire s_sof,s_eol,s_eof,
 output reg m_valid,input wire m_ready,
 output reg signed [31:0] m_sx,m_sy,m_j00,m_j01,m_j10,m_j11,
 output reg m_geometry_valid,m_j_valid,
 output reg [19:0] m_pixel_id,output reg [31:0] m_frame_id,
 output reg [15:0] m_param_version,output reg m_sof,m_eol,m_eof
);
 localparam CW=(IMAGE_WIDTH<=1)?1:$clog2(IMAGE_WIDTH);
 reg [CW-1:0] column;
 wire [CW-1:0] col=s_sof?0:column;
 reg first_row;
 reg signed [31:0] lx,ly;
 reg [68:0] left_tag;
 reg signed [31:0] line_x[0:IMAGE_WIDTH-1],line_y[0:IMAGE_WIDTH-1];
 reg [68:0] line_tag[0:IMAGE_WIDTH-1];
 wire [68:0] tag={s_geometry_valid,s_frame_id,s_param_version,s_pixel_id};
 wire signed [32:0] dx=$signed({s_sx[31],s_sx})-$signed({lx[31],lx});
 wire signed [32:0] dy=$signed({s_sy[31],s_sy})-$signed({ly[31],ly});
 wire signed [32:0] ux=$signed({s_sx[31],s_sx})-$signed({line_x[col][31],line_x[col]});
 wire signed [32:0] uy=$signed({s_sy[31],s_sy})-$signed({line_y[col][31],line_y[col]});
 assign s_ready=rstn&&(!m_valid||m_ready);
 always @(posedge clk) begin
  if(!rstn) begin m_valid<=0;column<=0;first_row<=1;left_tag<=0;m_j_valid<=0;end
  else if(s_ready) begin
   m_valid<=s_valid;
   if(s_valid) begin
    m_sx<=s_sx;m_sy<=s_sy;m_geometry_valid<=s_geometry_valid;
    {m_pixel_id,m_frame_id,m_param_version,m_sof,m_eol,m_eof}<=
      {s_pixel_id,s_frame_id,s_param_version,s_sof,s_eol,s_eof};
    m_j00<=dx[31:0];m_j10<=dy[31:0];m_j01<=ux[31:0];m_j11<=uy[31:0];
    m_j_valid<=!s_sof&&!first_row&&col!=0&&s_geometry_valid&&
      left_tag[68:20]=={1'b1,s_frame_id,s_param_version}&&
      line_tag[col][68:20]=={1'b1,s_frame_id,s_param_version}&&
      left_tag[19:0]+20'd1==s_pixel_id&&
      line_tag[col][19:0]+IMAGE_WIDTH==s_pixel_id&&
      dx[32]==dx[31]&&dy[32]==dy[31]&&ux[32]==ux[31]&&uy[32]==uy[31];
    line_x[col]<=s_sx;line_y[col]<=s_sy;line_tag[col]<=tag;
    lx<=s_sx;ly<=s_sy;left_tag<=tag;
    column<=s_eol?0:col+1'b1;
    if(s_sof) first_row<=1;
    if(s_eol) first_row<=0;
   end
  end
 end
endmodule

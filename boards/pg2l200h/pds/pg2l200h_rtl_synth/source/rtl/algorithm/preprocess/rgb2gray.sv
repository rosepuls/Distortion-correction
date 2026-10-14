`timescale 1ns/1ps

// RGB888 转 8 bit 灰度。
// 公式：Gray = (77*R + 150*G + 29*B) >> 8。
// LATENCY：1 个寄存器级；稳定输入时每拍处理 1 个像素。
module rgb2gray (
    // 时钟和低有效复位。
    input  wire        clk,
    input  wire        rst_n,
    // 输入 RGB888，打包顺序为 {R[7:0], G[7:0], B[7:0]}。
    input  wire [23:0] in_pixel,
    // 输入像素有效、帧首、行尾标志。
    input  wire        in_valid,
    input  wire        in_sof,
    input  wire        in_eol,
    // 输出灰度像素及与像素同步延迟的控制标志。
    output reg  [7:0]  out_pixel,
    output reg         out_valid,
    output reg         out_sof,
    output reg         out_eol
);

    wire [7:0] red   = in_pixel[23:16];
    wire [7:0] green = in_pixel[15:8];
    wire [7:0] blue  = in_pixel[7:0];

    // 三项最大总和为 65280，16 bit 足够保存。
    wire [15:0] red_term   = {8'd0, red} * 16'd77;
    wire [15:0] green_term = {8'd0, green} * 16'd150;
    wire [15:0] blue_term  = {8'd0, blue} * 16'd29;
    wire [15:0] weighted_sum = red_term + green_term + blue_term;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_pixel <= 8'd0;
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
        end else if (in_valid) begin
            out_pixel <= weighted_sum[15:8];
            out_valid <= 1'b1;
            out_sof   <= in_sof;
            out_eol   <= in_eol;
        end else begin
            out_pixel <= 8'd0;
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
        end
    end

endmodule

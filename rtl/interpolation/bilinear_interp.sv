`timescale 1ns/1ps

// RGB888 双线性插值模块。
// dx/dy 是 unsigned Q0.16；coord_valid=0 时输出黑色。
// p00/p10/p01/p11 分别是左上、右上、左下、右下四个采样点。
// LATENCY：1 个寄存器级；三个颜色通道并行计算。
module bilinear_interp (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [23:0] p00,
    input  wire [23:0] p10,
    input  wire [23:0] p01,
    input  wire [23:0] p11,
    input  wire [15:0] dx,
    input  wire [15:0] dy,
    input  wire        coord_valid,
    input  wire        in_valid,
    input  wire        in_sof,
    input  wire        in_eol,
    output reg  [23:0] out_pixel,
    output reg         out_valid,
    output reg         out_sof,
    output reg         out_eol
);

    // 单个颜色通道的两阶段插值：先沿 x 方向，再沿 y 方向。
    function automatic [7:0] interpolate_channel;
        input [7:0] p00_channel;
        input [7:0] p10_channel;
        input [7:0] p01_channel;
        input [7:0] p11_channel;
        input [15:0] dx_fraction;
        input [15:0] dy_fraction;
        reg signed [8:0] top_difference;
        reg signed [8:0] bottom_difference;
        reg signed [24:0] top_product;
        reg signed [24:0] bottom_product;
        reg signed [25:0] top_q16;
        reg signed [25:0] bottom_q16;
        reg signed [26:0] vertical_difference;
        reg signed [42:0] vertical_product;
        reg signed [43:0] result_q32;
        reg signed [43:0] integer_result;
        begin
            // 水平方向差值允许为负，因此显式使用 signed 和 9 bit。
            top_difference = $signed({1'b0, p10_channel}) - $signed({1'b0, p00_channel});
            bottom_difference = $signed({1'b0, p11_channel}) - $signed({1'b0, p01_channel});

            // 差值乘 Q0.16，结果保留 16 位小数。
            top_product = top_difference * $signed({1'b0, dx_fraction});  //第一个顶部横向插值改变的像素值
            bottom_product = bottom_difference * $signed({1'b0, dx_fraction});  //第一个底部横向插值改变的像素值
            top_q16 = $signed({1'b0, p00_channel, 16'd0}) + $signed({top_product[24], top_product});    //顶部插值后的像素值
            bottom_q16 = $signed({1'b0, p01_channel, 16'd0}) + $signed({bottom_product[24], bottom_product});   //底部插值后的像素值

            // 计算上下两条水平插值结果的差值，再乘 dy。
            vertical_difference = $signed({bottom_q16[25], bottom_q16}) - $signed({top_q16[25], top_q16});  // 上下两条水平插值结果的差值
            vertical_product = vertical_difference * $signed({1'b0, dy_fraction});      //垂直方向插值改变的像素值

            // 顶部结果左移 16 位与垂直乘积对齐，形成 Q32。
            result_q32 = $signed({{2{top_q16[25]}}, top_q16, 16'd0})        //顶部插值后的像素值加上垂直方向插值改变的像素值得到最终插值结果
                       + $signed({vertical_product[42], vertical_product});
            integer_result = result_q32 >>> 32;

            // 最终结果饱和到 8 bit，避免溢出回绕。
            if (integer_result < 0)
                interpolate_channel = 8'd0;
            else if (integer_result > 255)
                interpolate_channel = 8'd255;
            else
                interpolate_channel = integer_result[7:0];
        end
    endfunction

    // RGB 三通道使用相同的 dx/dy，但分别进行完整定点计算。
    wire [7:0] interpolated_red = interpolate_channel(
        p00[23:16], p10[23:16], p01[23:16], p11[23:16], dx, dy
    );
    wire [7:0] interpolated_green = interpolate_channel(
        p00[15:8], p10[15:8], p01[15:8], p11[15:8], dx, dy
    );
    wire [7:0] interpolated_blue = interpolate_channel(
        p00[7:0], p10[7:0], p01[7:0], p11[7:0], dx, dy
    );

    // coord_valid 是四邻点合法性的总开关；无效坐标不输出部分插值，直接黑色。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_pixel <= 24'd0;
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
        end else if (in_valid) begin
            out_pixel <= coord_valid ? {interpolated_red, interpolated_green, interpolated_blue} : 24'd0;
            out_valid <= 1'b1;
            out_sof   <= in_sof;
            out_eol   <= in_eol;
        end else begin
            out_pixel <= 24'd0;
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
        end
    end

endmodule

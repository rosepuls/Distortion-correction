`timescale 1ns/1ps

// 亮度与增益调整模块：Y_out = alpha * Y_in + beta。
// LATENCY：1 个寄存器级；cfg_gain 在帧首锁存，cfg_offset 为有符号整数。
// 接口说明：
//   clk/rst_n       ：时钟/低有效复位。
//   in_pixel       ：输入 8 bit 灰度像素。
//   in_valid       ：输入像素有效；为 0 时不产生有效输出。
//   in_sof/in_eol  ：帧首/行尾，与输入像素同拍。
//   cfg_gain       ：unsigned Q4.12 增益，例如 16'h1000 表示 1.0。
//   cfg_offset     ：signed 10 bit 亮度偏移。
//   out_pixel      ：经过增益、偏移和 0~255 饱和后的像素。
//   out_valid/...  ：与输出像素同步的有效、帧首、行尾标志。
module brightness_gain (
    input  wire               clk,
    input  wire               rst_n,
    input  wire [7:0]         in_pixel,
    input  wire                in_valid,
    input  wire                in_sof,
    input  wire                in_eol,
    input  wire [15:0]        cfg_gain,
    input  wire signed [9:0]  cfg_offset,
    output reg  [7:0]         out_pixel,
    output reg                out_valid,
    output reg                out_sof,
    output reg                out_eol
);

    // 配置只在帧首更新，保证同一帧所有像素使用相同的参数。
    reg [15:0]       gain_latched;
    reg signed [9:0] offset_latched;

    // 帧首像素要立即使用新的配置，因此这里对 sof 做前馈选择；
    // 后续像素则使用已经锁存的 gain/offset。
    wire [15:0] active_gain = (in_valid && in_sof) ? cfg_gain : gain_latched;
    wire signed [9:0] active_offset = (in_valid && in_sof) ? cfg_offset : offset_latched;

    // gain_product 保留 12 位小数：in_pixel * Q4.12 gain。
    wire [23:0] gain_product = {16'd0, in_pixel} * {8'd0, active_gain};

    // beta 是整数，需要左移 12 位才能与 gain_product 对齐。
    wire signed [24:0] offset_q12 = {{3{active_offset[9]}}, active_offset, 12'd0};
    wire signed [24:0] adjusted_q12 = $signed({1'b0, gain_product}) + offset_q12;

    // 算术右移去掉 Q4.12 的小数部分，负值会保持符号扩展。
    wire signed [24:0] adjusted_integer = adjusted_q12 >>> 12;

    // 输出像素不能回绕：小于 0 输出 0，大于 255 输出 255。
    function automatic [7:0] saturate_u8;
        input signed [24:0] value;
        begin
            if (value < 0)
                saturate_u8 = 8'd0;
            else if (value > 255)
                saturate_u8 = 8'd255;
            else
                saturate_u8 = value[7:0];
        end
    endfunction

    // 时序输出级：数据和 valid/sof/eol 在同一个时钟沿注册，保持对齐。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gain_latched   <= 16'h1000;
            offset_latched <= 10'sd0;
            out_pixel      <= 8'd0;
            out_valid      <= 1'b0;
            out_sof        <= 1'b0;
            out_eol        <= 1'b0;
        end else if (in_valid) begin
            if (in_sof) begin
                gain_latched   <= cfg_gain;
                offset_latched <= cfg_offset;
            end
            out_pixel <= saturate_u8(adjusted_integer);
            out_valid <= 1'b1;
            out_sof   <= in_sof;
            out_eol   <= in_eol;
        end else begin
            // 空拍不推进数据流，输出 valid 和同步标志清零。
            out_pixel <= 8'd0;
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
        end
    end

endmodule

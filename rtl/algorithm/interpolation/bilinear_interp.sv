`timescale 1ns/1ps

// RGB888 双线性插值模块。
// dx/dy 是 unsigned Q0.16；coord_valid=0 时输出黑色。
// p00/p10/p01/p11 分别是左上、右上、左下、右下四个采样点。
// LATENCY：4 个寄存器级。第一级完成三个颜色通道的横向插值，
// 第二级寄存纵向差分，第三极完成纵向乘法，第四级完成 Q32 求和、
// 移位与饱和。
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

    // 第一级：单个颜色通道沿 x 方向的插值，结果为 signed Q16。
    function automatic [25:0] horizontal_q16;
        input [7:0] p0_channel;
        input [7:0] p1_channel;
        input [15:0] dx_fraction;
        reg signed [8:0] difference;
        reg signed [24:0] product;
        reg signed [25:0] result_q16;
        begin
            difference = $signed({1'b0, p1_channel}) - $signed({1'b0, p0_channel});
            product = difference * $signed({1'b0, dx_fraction});
            result_q16 = $signed({1'b0, p0_channel, 16'd0})
                       + $signed({product[24], product});
            horizontal_q16 = result_q16;
        end
    endfunction

    // 第三级：只完成已寄存纵向差分的乘法，结果保持为 signed Q32。
    function automatic [43:0] vertical_product_q32;
        input signed [26:0] vertical_difference_input;
        input [15:0] dy_fraction;
        reg signed [42:0] vertical_product;
        begin
            vertical_product = vertical_difference_input * $signed({1'b0, dy_fraction});
            vertical_product_q32 = $signed({vertical_product[42], vertical_product});
        end
    endfunction

    // 第三级：将已寄存的纵向乘积与 top 项相加，再执行原有右移和饱和。
    function automatic [7:0] vertical_finalize_channel;
        input [25:0] top_q16_input;
        input [43:0] vertical_product_q32_input;
        reg signed [43:0] result_q32;
        reg signed [43:0] integer_result;
        begin
            result_q32 = $signed({{2{top_q16_input[25]}}, top_q16_input, 16'd0})
                       + $signed(vertical_product_q32_input);
            integer_result = result_q32 >>> 32;
            if (integer_result < 0)
                vertical_finalize_channel = 8'd0;
            else if (integer_result > 255)
                vertical_finalize_channel = 8'd255;
            else
                vertical_finalize_channel = integer_result[7:0];
        end
    endfunction

    reg signed [25:0] s1_top_red;
    reg signed [25:0] s1_top_green;
    reg signed [25:0] s1_top_blue;
    reg signed [25:0] s1_bottom_red;
    reg signed [25:0] s1_bottom_green;
    reg signed [25:0] s1_bottom_blue;
    reg        [15:0] s1_dy;
    reg               s1_coord_valid;
    reg               s1_valid;
    reg               s1_sof;
    reg               s1_eol;
    // 第二级：纵向差分和 top 项寄存器，切断差分进位链到 APM 乘法的路径。
    reg signed [25:0] s2d_top_red /* synthesis syn_preserve = 1 */;
    reg signed [25:0] s2d_top_green /* synthesis syn_preserve = 1 */;
    reg signed [25:0] s2d_top_blue /* synthesis syn_preserve = 1 */;
    reg signed [26:0] s2d_vertical_difference_red /* synthesis syn_preserve = 1 */;
    reg signed [26:0] s2d_vertical_difference_green /* synthesis syn_preserve = 1 */;
    reg signed [26:0] s2d_vertical_difference_blue /* synthesis syn_preserve = 1 */;
    reg        [15:0] s2d_dy /* synthesis syn_preserve = 1 */;
    reg               s2d_coord_valid /* synthesis syn_preserve = 1 */;
    reg               s2d_valid /* synthesis syn_preserve = 1 */;
    reg               s2d_sof /* synthesis syn_preserve = 1 */;
    reg               s2d_eol /* synthesis syn_preserve = 1 */;
    reg signed [25:0] s2_top_red;
    reg signed [25:0] s2_top_green;
    reg signed [25:0] s2_top_blue;
    reg signed [43:0] s2_vertical_product_red;
    reg signed [43:0] s2_vertical_product_green;
    reg signed [43:0] s2_vertical_product_blue;
    reg               s2_coord_valid;
    reg               s2_valid;
    reg               s2_sof;
    reg               s2_eol;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_top_red       <= 26'sd0;
            s1_top_green     <= 26'sd0;
            s1_top_blue      <= 26'sd0;
            s1_bottom_red    <= 26'sd0;
            s1_bottom_green  <= 26'sd0;
            s1_bottom_blue   <= 26'sd0;
            s1_dy            <= 16'd0;
            s1_coord_valid   <= 1'b0;
            s1_valid         <= 1'b0;
            s1_sof           <= 1'b0;
            s1_eol           <= 1'b0;
            s2d_coord_valid  <= 1'b0;
            s2d_valid        <= 1'b0;
            s2d_sof          <= 1'b0;
            s2d_eol          <= 1'b0;
            s2_coord_valid   <= 1'b0;
            s2_valid         <= 1'b0;
            s2_sof           <= 1'b0;
            s2_eol           <= 1'b0;
            out_pixel <= 24'd0;
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
        end else begin
            // 第一级：三个颜色通道共享 dx，分别产生上下两条 Q16 水平结果。
            s1_valid       <= in_valid;
            s1_sof         <= in_valid && in_sof;
            s1_eol         <= in_valid && in_eol;
            s1_coord_valid <= coord_valid;
            if (in_valid) begin
                s1_dy           <= dy;
                s1_top_red      <= horizontal_q16(p00[23:16], p10[23:16], dx);
                s1_top_green    <= horizontal_q16(p00[15:8],  p10[15:8],  dx);
                s1_top_blue     <= horizontal_q16(p00[7:0],   p10[7:0],   dx);
                s1_bottom_red   <= horizontal_q16(p01[23:16], p11[23:16], dx);
                s1_bottom_green <= horizontal_q16(p01[15:8],  p11[15:8],  dx);
                s1_bottom_blue  <= horizontal_q16(p01[7:0],   p11[7:0],   dx);
            end

            // 第四级：使用前一拍已寄存的纵向乘积完成最终插值。
            if (s2_valid) begin
                out_pixel <= s2_coord_valid ? {
                    vertical_finalize_channel(s2_top_red,   s2_vertical_product_red),
                    vertical_finalize_channel(s2_top_green, s2_vertical_product_green),
                    vertical_finalize_channel(s2_top_blue,  s2_vertical_product_blue)
                } : 24'd0;
                out_valid <= 1'b1;
                out_sof   <= s2_sof;
                out_eol   <= s2_eol;
            end else begin
                out_pixel <= 24'd0;
                out_valid <= 1'b0;
                out_sof   <= 1'b0;
                out_eol   <= 1'b0;
            end

            // 第三级：锁存纵向乘积及其对应的 top 项和 sideband。
            s2_valid       <= s2d_valid;
            s2_sof         <= s2d_sof;
            s2_eol         <= s2d_eol;
            s2_coord_valid <= s2d_coord_valid;
            if (s2d_valid) begin
                s2_top_red              <= s2d_top_red;
                s2_top_green            <= s2d_top_green;
                s2_top_blue             <= s2d_top_blue;
                s2_vertical_product_red <= vertical_product_q32(s2d_vertical_difference_red, s2d_dy);
                s2_vertical_product_green <= vertical_product_q32(s2d_vertical_difference_green, s2d_dy);
                s2_vertical_product_blue <= vertical_product_q32(s2d_vertical_difference_blue, s2d_dy);
            end

            // 第二级：只完成纵向差分，将差分、top 项、dy 和 sideband
            // 一起寄存，避免差分进位链进入下一拍的 APM 乘法。
            s2d_valid       <= s1_valid;
            s2d_sof         <= s1_sof;
            s2d_eol         <= s1_eol;
            s2d_coord_valid <= s1_coord_valid;
            if (s1_valid) begin
                s2d_top_red <= s1_top_red;
                s2d_top_green <= s1_top_green;
                s2d_top_blue <= s1_top_blue;
                s2d_vertical_difference_red <=
                    $signed({s1_bottom_red[25], s1_bottom_red}) -
                    $signed({s1_top_red[25], s1_top_red});
                s2d_vertical_difference_green <=
                    $signed({s1_bottom_green[25], s1_bottom_green}) -
                    $signed({s1_top_green[25], s1_top_green});
                s2d_vertical_difference_blue <=
                    $signed({s1_bottom_blue[25], s1_bottom_blue}) -
                    $signed({s1_top_blue[25], s1_top_blue});
                s2d_dy <= s1_dy;
            end
        end
    end

endmodule

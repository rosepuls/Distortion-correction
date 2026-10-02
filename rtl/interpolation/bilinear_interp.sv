`timescale 1ns/1ps

// RGB888 双线性插值模块。
// dx/dy 是 unsigned Q0.16；coord_valid=0 时输出黑色。
// p00/p10/p01/p11 分别是左上、右上、左下、右下四个采样点。
// LATENCY：2 个寄存器级。第一级完成三个颜色通道的横向插值，
// 第二级完成纵向插值与饱和，避免把两次乘法链压进同一个时钟周期。
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

    // 第二级：由两条 Q16 水平插值结果完成 y 方向插值，并饱和到 RGB8。
    function automatic [7:0] vertical_interpolate_channel;
        input [25:0] top_q16_input;
        input [25:0] bottom_q16_input;
        input [15:0] dy_fraction;
        reg signed [26:0] vertical_difference;
        reg signed [42:0] vertical_product;
        reg signed [43:0] result_q32;
        reg signed [43:0] integer_result;
        begin
            vertical_difference = $signed({bottom_q16_input[25], bottom_q16_input})
                                - $signed({top_q16_input[25], top_q16_input});
            vertical_product = vertical_difference * $signed({1'b0, dy_fraction});
            result_q32 = $signed({{2{top_q16_input[25]}}, top_q16_input, 16'd0})
                       + $signed({vertical_product[42], vertical_product});
            integer_result = result_q32 >>> 32;
            if (integer_result < 0)
                vertical_interpolate_channel = 8'd0;
            else if (integer_result > 255)
                vertical_interpolate_channel = 8'd255;
            else
                vertical_interpolate_channel = integer_result[7:0];
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
            s1_dy          <= dy;
            if (in_valid) begin
                s1_top_red      <= horizontal_q16(p00[23:16], p10[23:16], dx);
                s1_top_green    <= horizontal_q16(p00[15:8],  p10[15:8],  dx);
                s1_top_blue     <= horizontal_q16(p00[7:0],   p10[7:0],   dx);
                s1_bottom_red   <= horizontal_q16(p01[23:16], p11[23:16], dx);
                s1_bottom_green <= horizontal_q16(p01[15:8],  p11[15:8],  dx);
                s1_bottom_blue  <= horizontal_q16(p01[7:0],   p11[7:0],   dx);
            end else begin
                s1_top_red      <= 26'sd0;
                s1_top_green    <= 26'sd0;
                s1_top_blue     <= 26'sd0;
                s1_bottom_red   <= 26'sd0;
                s1_bottom_green <= 26'sd0;
                s1_bottom_blue  <= 26'sd0;
            end

            // 第二级：使用前一拍的 Q16 结果完成垂直插值。
            if (s1_valid) begin
                out_pixel <= s1_coord_valid ? {
                    vertical_interpolate_channel(s1_top_red,   s1_bottom_red,   s1_dy),
                    vertical_interpolate_channel(s1_top_green, s1_bottom_green, s1_dy),
                    vertical_interpolate_channel(s1_top_blue,  s1_bottom_blue,  s1_dy)
                } : 24'd0;
                out_valid <= 1'b1;
                out_sof   <= s1_sof;
                out_eol   <= s1_eol;
            end else begin
                out_pixel <= 24'd0;
                out_valid <= 1'b0;
                out_sof   <= 1'b0;
                out_eol   <= 1'b0;
            end
        end
    end

endmodule

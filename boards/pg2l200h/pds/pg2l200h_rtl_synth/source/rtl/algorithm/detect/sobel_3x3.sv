`timescale 1ns/1ps

// Sobel 边缘检测：G = |Gx| + |Gy|，输出保留 12 bit。
// p00~p22 是 3x3 灰度窗口；in_* 是输入窗口控制；out_gradient/out_* 是结果。
// LATENCY：1 个寄存器级。
module sobel_3x3 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  p00, input wire [7:0] p01, input wire [7:0] p02,
    input  wire [7:0]  p10, input wire [7:0] p11, input wire [7:0] p12,
    input  wire [7:0]  p20, input wire [7:0] p21, input wire [7:0] p22,
    input  wire        in_valid,
    input  wire        in_sof,
    input  wire        in_eol,
    output reg  [11:0] out_gradient,
    output reg         out_valid,
    output reg         out_sof,
    output reg         out_eol
);

    // 先将正系数和负系数分开累加，避免无符号输入直接参与有符号运算。
    wire [10:0] gx_positive = {3'd0, p02} + ({3'd0, p12} << 1) + {3'd0, p22};
    wire [10:0] gx_negative = {3'd0, p00} + ({3'd0, p10} << 1) + {3'd0, p20};
    wire [10:0] gy_positive = {3'd0, p20} + ({3'd0, p21} << 1) + {3'd0, p22};
    wire [10:0] gy_negative = {3'd0, p00} + ({3'd0, p01} << 1) + {3'd0, p02};

    // Sobel 的 Gx/Gy 范围是 -1020~1020，因此使用 signed 12 bit。
    wire signed [11:0] gx = $signed({1'b0, gx_positive}) - $signed({1'b0, gx_negative});
    wire signed [11:0] gy = $signed({1'b0, gy_positive}) - $signed({1'b0, gy_negative});
    wire [10:0] abs_gx = gx[11] ? -gx : gx;
    wire [10:0] abs_gy = gy[11] ? -gy : gy;

    // L1 梯度幅值，最大约 2040，保留 12 bit 供后级阈值使用。
    wire [11:0] gradient = {1'b0, abs_gx} + {1'b0, abs_gy};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_gradient <= 12'd0;
            out_valid    <= 1'b0;
            out_sof      <= 1'b0;
            out_eol      <= 1'b0;
        end else if (in_valid) begin
            out_gradient <= gradient;
            out_valid    <= 1'b1;
            out_sof      <= in_sof;
            out_eol      <= in_eol;
        end else begin
            out_gradient <= 12'd0;
            out_valid    <= 1'b0;
            out_sof      <= 1'b0;
            out_eol      <= 1'b0;
        end
    end

endmodule

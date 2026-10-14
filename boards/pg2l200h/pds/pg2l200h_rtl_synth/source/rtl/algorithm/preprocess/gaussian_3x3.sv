`timescale 1ns/1ps

// 3x3 高斯滤波：核为 [1 2 1; 2 4 2; 1 2 1] / 16。
// p00~p22 是窗口生成器输出，p11 对应当前中心像素。
// in_valid/in_sof/in_eol 是窗口控制；out_pixel/out_* 是滤波结果及同步控制。
// LATENCY：1 个寄存器级；除以 16 用右移 4 位完成。
module gaussian_3x3 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] p00, input wire [7:0] p01, input wire [7:0] p02,
    input  wire [7:0] p10, input wire [7:0] p11, input wire [7:0] p12,
    input  wire [7:0] p20, input wire [7:0] p21, input wire [7:0] p22,
    input  wire       in_valid,
    input  wire       in_sof,
    input  wire       in_eol,
    output reg  [7:0] out_pixel,
    output reg        out_valid,
    output reg        out_sof,
    output reg        out_eol
);

    // 12 bit 累加器足以容纳最大值 255*16=4080。
    // 乘 2/4 用移位代替乘法器，最后 >>4 完成归一化。
    wire [11:0] sum = {4'd0, p00}
                    + ({4'd0, p01} << 1)
                    + {4'd0, p02}
                    + ({4'd0, p10} << 1)
                    + ({4'd0, p11} << 2)
                    + ({4'd0, p12} << 1)
                    + {4'd0, p20}
                    + ({4'd0, p21} << 1)
                    + {4'd0, p22};

    // 仅在输入窗口有效时注册结果，空拍时清除输出 valid。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_pixel <= 8'd0;
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
        end else if (in_valid) begin
            out_pixel <= sum[11:4];
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

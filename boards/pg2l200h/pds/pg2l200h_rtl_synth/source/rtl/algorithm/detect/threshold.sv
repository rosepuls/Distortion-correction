`timescale 1ns/1ps

// 12 bit Sobel 梯度二值化模块。
// in_gradient 是梯度输入；cfg_threshold 在帧首锁存；out_pixel=1 表示 G>T。
// in_valid/in_sof/in_eol 和 out_valid/out_sof/out_eol 负责流控制对齐。
// LATENCY：1 个寄存器级。
module threshold (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] in_gradient,
    input  wire        in_valid,
    input  wire        in_sof,
    input  wire        in_eol,
    input  wire [11:0] cfg_threshold,
    output reg         out_pixel,
    output reg         out_valid,
    output reg         out_sof,
    output reg         out_eol
);

    // 阈值寄存器保证一帧内不会因软件修改配置而改变判断标准。
    reg [11:0] threshold_latched;
    wire [11:0] active_threshold = (in_valid && in_sof) ? cfg_threshold : threshold_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            threshold_latched <= 12'd0;
            out_pixel         <= 1'b0;
            out_valid         <= 1'b0;
            out_sof           <= 1'b0;
            out_eol           <= 1'b0;
        end else if (in_valid) begin
            if (in_sof)
            threshold_latched <= cfg_threshold;
            // 项目规则使用严格大于：等于阈值也判为背景 0。
            out_pixel <= (in_gradient > active_threshold);
            out_valid <= 1'b1;
            out_sof   <= in_sof;
            out_eol   <= in_eol;
        end else begin
            out_pixel <= 1'b0;
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
        end
    end

endmodule

`timescale 1ns/1ps

// 二值 3x3 形态学模块：cfg_dilate=0 为腐蚀，cfg_dilate=1 为膨胀。
// p00~p22 是 1 bit 二值窗口；cfg_dilate 在帧首锁存；out_pixel 为结果。
// 图像外零填充时，腐蚀使用 AND，膨胀使用 OR；LATENCY：1 个寄存器级。
module morphology (
    input  wire clk,
    input  wire rst_n,
    input  wire p00, input wire p01, input wire p02,
    input  wire p10, input wire p11, input wire p12,
    input  wire p20, input wire p21, input wire p22,
    input  wire in_valid,
    input  wire in_sof,
    input  wire in_eol,
    input  wire cfg_dilate,
    output reg  out_pixel,
    output reg  out_valid,
    output reg  out_sof,
    output reg  out_eol
);

    // 保存本帧的模式：1 个前景点即可膨胀，9 个点全为前景才腐蚀通过。
    reg dilate_latched;
    wire active_dilate = (in_valid && in_sof) ? cfg_dilate : dilate_latched;
    wire any_foreground = p00 | p01 | p02 | p10 | p11 | p12 | p20 | p21 | p22;
    wire all_foreground = p00 & p01 & p02 & p10 & p11 & p12 & p20 & p21 & p22;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dilate_latched <= 1'b0;
            out_pixel      <= 1'b0;
            out_valid      <= 1'b0;
            out_sof        <= 1'b0;
            out_eol        <= 1'b0;
        end else if (in_valid) begin
            if (in_sof)
                dilate_latched <= cfg_dilate;
            // 根据当前模式选择 OR（膨胀）或 AND（腐蚀）的组合结果。
            out_pixel <= active_dilate ? any_foreground : all_foreground;
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

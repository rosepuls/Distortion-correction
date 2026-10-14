`timescale 1ns/1ps

// Gamma 查找表模块：使用两个 256 x 8 bit LUT bank 完成 Gamma 映射。
// LATENCY：1 个寄存器级。
// 接口说明：clk/rst_n 为时钟/低有效复位；in_pixel 为 LUT 地址；
// in_valid/in_sof/in_eol 为输入控制；cfg_enable 为 Gamma 旁路选择；
// cfg_bank_select 选择当前 bank；cfg_write_* 用于配置 LUT；
// out_pixel/out_* 为查表结果及同步控制。
module gamma_lut (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] in_pixel,
    input  wire       in_valid,
    input  wire       in_sof,
    input  wire       in_eol,
    input  wire       cfg_enable,
    input  wire       cfg_bank_select,
    input  wire       cfg_write_enable,
    input  wire       cfg_write_bank,
    input  wire [7:0] cfg_write_address,
    input  wire [7:0] cfg_write_data,
    output reg  [7:0] out_pixel,
    output reg        out_valid,
    output reg        out_sof,
    output reg        out_eol
);

    // 双 bank 结构允许软件在未使用的 bank 中准备下一张 Gamma 表。
    reg [7:0] lut_bank0 [0:255];
    reg [7:0] lut_bank1 [0:255];
    reg       enable_latched;
    reg       bank_latched;

    // 帧首使用当前 cfg，其他像素使用本帧锁存的配置。
    wire active_enable = (in_valid && in_sof) ? cfg_enable : enable_latched;
    wire active_bank = (in_valid && in_sof) ? cfg_bank_select : bank_latched;

    // LUT 是异步读：输入像素值直接作为 256 深度 RAM 的地址。
    wire [7:0] lookup_pixel = active_bank ? lut_bank1[in_pixel] : lut_bank0[in_pixel];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable_latched <= 1'b0;
            bank_latched   <= 1'b0;
            out_pixel      <= 8'd0;
            out_valid      <= 1'b0;
            out_sof        <= 1'b0;
            out_eol        <= 1'b0;
        end else begin
            // LUT 写端口通常由寄存器总线驱动，建议在帧间写入。
            if (cfg_write_enable) begin
                if (cfg_write_bank)
                    lut_bank1[cfg_write_address] <= cfg_write_data;
                else
                    lut_bank0[cfg_write_address] <= cfg_write_data;
            end

            if (in_valid) begin
                if (in_sof) begin
                    enable_latched <= cfg_enable;
                    bank_latched   <= cfg_bank_select;
                end
                // 未启用 Gamma 时保留原值，启用时输出 LUT 数据。
                out_pixel <= active_enable ? lookup_pixel : in_pixel;
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
    end

endmodule

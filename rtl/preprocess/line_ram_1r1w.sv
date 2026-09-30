`timescale 1ns/1ps

// 单时钟、1 读 1 写的行缓存 RAM 封装。
// 读端口为同步读：rd_en 有效的时钟沿后，rd_data 给出 rd_addr 的旧内容。
// 读写同一地址时，仿真语义为 read-before-write（先读旧数据，再写新数据）。
// 使用 2 的整数次幂深度，避免 PDS 按地址位宽扩展不规则深度时生成大量反馈 mux。
module line_ram_1r1w #(
    parameter integer ADDR_WIDTH = 11,
    parameter integer DATA_WIDTH = 8
) (
    input  wire                  clk,
    input  wire                  rd_en,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output reg  [DATA_WIDTH-1:0] rd_data,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data
);

    // PDS/FPGA 会将此简单双端口同步 RAM 模式映射为片上 DRM。
    reg [DATA_WIDTH-1:0] mem [0:(1 << ADDR_WIDTH)-1];

    always @(posedge clk) begin
        if (rd_en)
            rd_data <= mem[rd_addr];

        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

endmodule

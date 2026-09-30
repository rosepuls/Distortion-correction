`timescale 1ns/1ps

// 3x3 窗口的双行缓存模块。
// 作用：对每个输入列同时提供 y-2、y-1、y 三个像素，供 window_3x3 使用。
// 参数：IMAGE_WIDTH/IMAGE_HEIGHT 是图像尺寸；PIXEL_WIDTH 是灰度像素位宽。
// 接口说明：clk/rst_n 为时钟/复位；in_pixel 为输入像素；in_valid/in_sof/in_eol
// 为输入控制；tap_top/tap_middle/tap_bottom 为三行同列像素；out_* 为同步控制；
// out_synthetic=1 表示当前数据是帧尾自动生成的零填充行。
//
// 行缓存使用同步读 RAM，内部为两级寄存器路径；相对一次输入采样，tap 和 out_*
// 在下一时钟周期有效，每拍仍可接收一个像素。帧尾自动生成两行零数据，因此下一帧
// SOF 前应保留 2*IMAGE_WIDTH 个空拍。
module line_buffer_3x3 #(
    parameter integer IMAGE_WIDTH  = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer PIXEL_WIDTH  = 8
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [PIXEL_WIDTH-1:0] in_pixel,
    input  wire                   in_valid,
    input  wire                   in_sof,
    input  wire                   in_eol,
    output reg  [PIXEL_WIDTH-1:0] tap_top,
    output reg  [PIXEL_WIDTH-1:0] tap_middle,
    output reg  [PIXEL_WIDTH-1:0] tap_bottom,
    output reg                    out_valid,
    output reg                    out_sof,
    output reg                    out_eol,
    output reg                    out_synthetic
);

    // 行 RAM 的物理深度按列地址宽度向上取 2 的整数次幂。
    localparam integer COLUMN_BITS = (IMAGE_WIDTH <= 1) ? 1 : $clog2(IMAGE_WIDTH);
    localparam integer ROW_BITS    = (IMAGE_HEIGHT <= 1) ? 2 : $clog2(IMAGE_HEIGHT + 2);

    reg [COLUMN_BITS-1:0] column_index;
    reg [ROW_BITS-1:0]    row_index;
    reg [COLUMN_BITS-1:0] flush_column;
    reg                   flush_active;
    reg                   flush_second_line;

    // RAM 读结果在请求后的下一拍有效；pipe_* 保存与该读结果严格对应的控制信息。
    reg [PIXEL_WIDTH-1:0] pipe_bottom;
    reg [COLUMN_BITS-1:0] pipe_column;
    reg                   pipe_valid;
    reg                   pipe_sof;
    reg                   pipe_eol;
    reg                   pipe_synthetic;
    reg                   pipe_has_top;
    reg                   pipe_has_middle;

    wire [PIXEL_WIDTH-1:0] previous_read_data;
    wire [PIXEL_WIDTH-1:0] older_read_data;

    // SOF 到来时立即将当前输入重新解释为坐标 (0,0)。
    wire [COLUMN_BITS-1:0] input_column = in_sof ? {COLUMN_BITS{1'b0}} : column_index;
    wire [ROW_BITS-1:0]    input_row    = in_sof ? {ROW_BITS{1'b0}} : row_index;

    // 一个 event 表示向两条行 RAM 发出一次读请求，同时写入当前 bottom 像素。
    // 真实输入优先于帧尾排空；接口约定要求下一帧 SOF 只在排空结束后到来。
    wire                   event_valid      = in_valid || flush_active;
    wire                   event_is_real    = in_valid;
    wire [COLUMN_BITS-1:0] event_column     = event_is_real ? input_column : flush_column;
    wire [PIXEL_WIDTH-1:0] event_pixel      = event_is_real ? in_pixel : {PIXEL_WIDTH{1'b0}};
    wire                   event_sof        = event_is_real && in_sof;
    wire                   event_eol        = event_is_real ? in_eol
                                                   : (flush_column == IMAGE_WIDTH - 1);
    wire                   event_synthetic  = !event_is_real;
    wire                   event_has_top    = event_is_real ? (input_row >= 2) : 1'b1;
    wire                   event_has_middle = event_is_real ? (input_row >= 1) : 1'b1;

    // previous_line：读出 y-1，并把当前 bottom 写入，供下一行使用。
    line_ram_1r1w #(
        .ADDR_WIDTH(COLUMN_BITS),
        .DATA_WIDTH(PIXEL_WIDTH)
    ) previous_line_ram (
        .clk(clk),
        .rd_en(event_valid), .rd_addr(event_column), .rd_data(previous_read_data),
        .wr_en(event_valid), .wr_addr(event_column), .wr_data(event_pixel)
    );

    // older_line：读出 y-2。previous_read_data 对应 pipe_* 这一拍的旧 y-1 数据，
    // 因此通过独立写端口在下一拍写入 older_line，保持每拍一个像素的吞吐率。
    line_ram_1r1w #(
        .ADDR_WIDTH(COLUMN_BITS),
        .DATA_WIDTH(PIXEL_WIDTH)
    ) older_line_ram (
        .clk(clk),
        .rd_en(event_valid), .rd_addr(event_column), .rd_data(older_read_data),
        .wr_en(pipe_valid), .wr_addr(pipe_column), .wr_data(previous_read_data)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tap_top           <= {PIXEL_WIDTH{1'b0}};
            tap_middle        <= {PIXEL_WIDTH{1'b0}};
            tap_bottom        <= {PIXEL_WIDTH{1'b0}};
            out_valid         <= 1'b0;
            out_sof           <= 1'b0;
            out_eol           <= 1'b0;
            out_synthetic     <= 1'b0;
            column_index      <= {COLUMN_BITS{1'b0}};
            row_index         <= {ROW_BITS{1'b0}};
            flush_column      <= {COLUMN_BITS{1'b0}};
            flush_active      <= 1'b0;
            flush_second_line <= 1'b0;
            pipe_bottom       <= {PIXEL_WIDTH{1'b0}};
            pipe_column       <= {COLUMN_BITS{1'b0}};
            pipe_valid        <= 1'b0;
            pipe_sof          <= 1'b0;
            pipe_eol          <= 1'b0;
            pipe_synthetic    <= 1'b0;
            pipe_has_top      <= 1'b0;
            pipe_has_middle   <= 1'b0;
        end else begin
            // 输出前一拍 RAM 请求的结果；所有像素和控制位均由同一 pipe_* 对齐。
            out_valid     <= pipe_valid;
            out_sof       <= pipe_valid && pipe_sof;
            out_eol       <= pipe_valid && pipe_eol;
            out_synthetic <= pipe_valid && pipe_synthetic;
            if (pipe_valid) begin
                tap_top    <= pipe_has_top    ? older_read_data    : {PIXEL_WIDTH{1'b0}};
                tap_middle <= pipe_has_middle ? previous_read_data : {PIXEL_WIDTH{1'b0}};
                tap_bottom <= pipe_bottom;
            end else begin
                tap_top    <= {PIXEL_WIDTH{1'b0}};
                tap_middle <= {PIXEL_WIDTH{1'b0}};
                tap_bottom <= {PIXEL_WIDTH{1'b0}};
            end

            // 为当前请求记录下一拍输出所需的元数据。
            pipe_valid <= event_valid;
            if (event_valid) begin
                pipe_bottom     <= event_pixel;
                pipe_column     <= event_column;
                pipe_sof        <= event_sof;
                pipe_eol        <= event_eol;
                pipe_synthetic  <= event_synthetic;
                pipe_has_top    <= event_has_top;
                pipe_has_middle <= event_has_middle;
            end else begin
                pipe_bottom     <= {PIXEL_WIDTH{1'b0}};
                pipe_column     <= {COLUMN_BITS{1'b0}};
                pipe_sof        <= 1'b0;
                pipe_eol        <= 1'b0;
                pipe_synthetic  <= 1'b0;
                pipe_has_top    <= 1'b0;
                pipe_has_middle <= 1'b0;
            end

            if (event_is_real) begin
                if (in_eol) begin
                    column_index <= {COLUMN_BITS{1'b0}};
                    row_index    <= input_row + 1'b1;
                    if (input_row == IMAGE_HEIGHT - 1) begin
                        flush_active      <= 1'b1;
                        flush_second_line <= 1'b0;
                        flush_column      <= {COLUMN_BITS{1'b0}};
                    end
                end else begin
                    column_index <= input_column + 1'b1;
                    row_index    <= input_row;
                end
            end else if (flush_active) begin
                if (flush_column == IMAGE_WIDTH - 1) begin
                    flush_column <= {COLUMN_BITS{1'b0}};
                    if (flush_second_line) begin
                        flush_active      <= 1'b0;
                        flush_second_line <= 1'b0;
                    end else begin
                        flush_second_line <= 1'b1;
                    end
                end else begin
                    flush_column <= flush_column + 1'b1;
                end
            end
        end
    end

endmodule

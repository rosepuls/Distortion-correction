`timescale 1ns/1ps

// 3x3 窗口生成器：将三行同列 tap 展开成中心对齐的九个像素。
// 输出图像保持 IMAGE_WIDTH x IMAGE_HEIGHT，所有越界位置补 0。
// tap_top/middle/bottom 来自 line_buffer_3x3；p11 是当前窗口中心。
// in_valid/in_sof/in_eol/in_synthetic 是输入控制；out_* 是窗口控制输出。
// 行尾的最右窗口先暂存，在下一行 x=0 时释放，保证输出仍是光栅顺序。
module window_3x3 #(
    parameter integer IMAGE_WIDTH  = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer PIXEL_WIDTH  = 8
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [PIXEL_WIDTH-1:0] tap_top,
    input  wire [PIXEL_WIDTH-1:0] tap_middle,
    input  wire [PIXEL_WIDTH-1:0] tap_bottom,
    input  wire                   in_valid,
    input  wire                   in_sof,
    input  wire                   in_eol,
    input  wire                   in_synthetic,
    output reg  [PIXEL_WIDTH-1:0] p00,
    output reg  [PIXEL_WIDTH-1:0] p01,
    output reg  [PIXEL_WIDTH-1:0] p02,
    output reg  [PIXEL_WIDTH-1:0] p10,
    output reg  [PIXEL_WIDTH-1:0] p11,
    output reg  [PIXEL_WIDTH-1:0] p12,
    output reg  [PIXEL_WIDTH-1:0] p20,
    output reg  [PIXEL_WIDTH-1:0] p21,
    output reg  [PIXEL_WIDTH-1:0] p22,
    output reg                    out_valid,
    output reg                    out_sof,
    output reg                    out_eol
);

    localparam integer COLUMN_BITS = (IMAGE_WIDTH <= 1) ? 1 : $clog2(IMAGE_WIDTH);
    localparam integer ROW_BITS    = (IMAGE_HEIGHT <= 1) ? 2 : $clog2(IMAGE_HEIGHT + 2);

    // 每组寄存器保存某一行最近两个列值，用于形成 [x-2,x-1,x] 窗口。
    reg [PIXEL_WIDTH-1:0] top_left;
    reg [PIXEL_WIDTH-1:0] top_middle;
    reg [PIXEL_WIDTH-1:0] middle_left;
    reg [PIXEL_WIDTH-1:0] middle_middle;
    reg [PIXEL_WIDTH-1:0] bottom_left;
    reg [PIXEL_WIDTH-1:0] bottom_middle;

    reg [COLUMN_BITS-1:0] column_index;
    reg [ROW_BITS-1:0]    row_index;

    // 当前行结束时，x=IMAGE_WIDTH-1 的窗口需要下一个输入时刻才能发出。
    reg                    pending_right;
    reg [PIXEL_WIDTH-1:0] pending_p00, pending_p01, pending_p02;
    reg [PIXEL_WIDTH-1:0] pending_p10, pending_p11, pending_p12;
    reg [PIXEL_WIDTH-1:0] pending_p20, pending_p21, pending_p22;

    // SOF 让本模块重新从 (0,0) 计数，避免上一帧状态污染下一帧。
    wire [COLUMN_BITS-1:0] current_column = in_sof ? {COLUMN_BITS{1'b0}} : column_index;
    wire [ROW_BITS-1:0]    current_row    = in_sof ? {ROW_BITS{1'b0}} : row_index;

    // x=0 没有左邻点，所以第一个可以输出的列是输入列 x=1；
    // 真实行和第一条虚拟底部行都可以形成有效中心。
    wire direct_window = (current_column >= 1)
                       && (current_row >= 1)
                       && (current_row <= IMAGE_HEIGHT);
    wire queue_right = in_eol
                     && (current_row >= 1)
                     && (current_row <= IMAGE_HEIGHT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 清空水平历史，复位后不会输出伪窗口。
            top_left       <= {PIXEL_WIDTH{1'b0}};
            top_middle     <= {PIXEL_WIDTH{1'b0}};
            middle_left    <= {PIXEL_WIDTH{1'b0}};
            middle_middle  <= {PIXEL_WIDTH{1'b0}};
            bottom_left    <= {PIXEL_WIDTH{1'b0}};
            bottom_middle  <= {PIXEL_WIDTH{1'b0}};
            column_index   <= {COLUMN_BITS{1'b0}};
            row_index      <= {ROW_BITS{1'b0}};
            pending_right  <= 1'b0;
            pending_p00    <= {PIXEL_WIDTH{1'b0}};
            pending_p01    <= {PIXEL_WIDTH{1'b0}};
            pending_p02    <= {PIXEL_WIDTH{1'b0}};
            pending_p10    <= {PIXEL_WIDTH{1'b0}};
            pending_p11    <= {PIXEL_WIDTH{1'b0}};
            pending_p12    <= {PIXEL_WIDTH{1'b0}};
            pending_p20    <= {PIXEL_WIDTH{1'b0}};
            pending_p21    <= {PIXEL_WIDTH{1'b0}};
            pending_p22    <= {PIXEL_WIDTH{1'b0}};
            p00            <= {PIXEL_WIDTH{1'b0}};
            p01            <= {PIXEL_WIDTH{1'b0}};
            p02            <= {PIXEL_WIDTH{1'b0}};
            p10            <= {PIXEL_WIDTH{1'b0}};
            p11            <= {PIXEL_WIDTH{1'b0}};
            p12            <= {PIXEL_WIDTH{1'b0}};
            p20            <= {PIXEL_WIDTH{1'b0}};
            p21            <= {PIXEL_WIDTH{1'b0}};
            p22            <= {PIXEL_WIDTH{1'b0}};
            out_valid      <= 1'b0;
            out_sof        <= 1'b0;
            out_eol        <= 1'b0;
        end else if (in_valid) begin
            // 在每个有效 tap 到来后，三行移位寄存器都向左移动一列。
            // 帧首或新行第 0 列左侧都没有同一行历史值，显式补零。
            // column_index 在上一行 EOL 后归零，因此可识别每一行的首个有效 tap。
            if (in_sof || (column_index == {COLUMN_BITS{1'b0}})) begin
                top_left      <= {PIXEL_WIDTH{1'b0}};
                top_middle    <= tap_top;
                middle_left   <= {PIXEL_WIDTH{1'b0}};
                middle_middle <= tap_middle;
                bottom_left   <= {PIXEL_WIDTH{1'b0}};
                bottom_middle <= tap_bottom;
                pending_right <= 1'b0;
            end else begin
                top_left      <= top_middle;
                top_middle    <= tap_top;
                middle_left   <= middle_middle;
                middle_middle <= tap_middle;
                bottom_left   <= bottom_middle;
                bottom_middle <= tap_bottom;
            end

            // eol 只在有效输入上改变行计数，下一有效 tap 从下一行第 0 列开始。
            if (in_eol) begin
                column_index <= {COLUMN_BITS{1'b0}};
                row_index    <= current_row + 1'b1;
            end else begin
                column_index <= current_column + 1'b1;
                row_index    <= current_row;
            end

            // 处理每一行最右边那个“补出来的 3×3 窗口。
            if (pending_right && !in_sof) begin
                p00       <= pending_p00;
                p01       <= pending_p01;
                p02       <= pending_p02;
                p10       <= pending_p10;
                p11       <= pending_p11;
                p12       <= pending_p12;
                p20       <= pending_p20;
                p21       <= pending_p21;
                p22       <= pending_p22;
                out_valid <= 1'b1;
                out_sof   <= 1'b0;
                out_eol   <= 1'b1;
                pending_right <= 1'b0;
            end else if (direct_window) begin
                // 当前 tap 作为窗口最右列，移位寄存器提供左两列。
                p00       <= top_left;
                p01       <= top_middle;
                p02       <= tap_top;
                p10       <= middle_left;
                p11       <= middle_middle;
                p12       <= tap_middle;
                p20       <= bottom_left;
                p21       <= bottom_middle;
                p22       <= tap_bottom;
                out_valid <= 1'b1;
                out_sof   <= (current_row == 1) && (current_column == 1);
                out_eol   <= 1'b0;
            end else begin
                // 前两列或最后一条排空行的无效周期不产生窗口。
                p00       <= {PIXEL_WIDTH{1'b0}};
                p01       <= {PIXEL_WIDTH{1'b0}};
                p02       <= {PIXEL_WIDTH{1'b0}};
                p10       <= {PIXEL_WIDTH{1'b0}};
                p11       <= {PIXEL_WIDTH{1'b0}};
                p12       <= {PIXEL_WIDTH{1'b0}};
                p20       <= {PIXEL_WIDTH{1'b0}};
                p21       <= {PIXEL_WIDTH{1'b0}};
                p22       <= {PIXEL_WIDTH{1'b0}};
                out_valid <= 1'b0;
                out_sof   <= 1'b0;
                out_eol   <= 1'b0;
            end

            // 行尾把 [W-2,W-1,0] 作为下一周期要输出的右边界窗口保存。
            if (queue_right) begin
                pending_p00   <= top_middle;
                pending_p01   <= tap_top;
                pending_p02   <= {PIXEL_WIDTH{1'b0}};
                pending_p10   <= middle_middle;
                pending_p11   <= tap_middle;
                pending_p12   <= {PIXEL_WIDTH{1'b0}};
                pending_p20   <= bottom_middle;
                pending_p21   <= tap_bottom;
                pending_p22   <= {PIXEL_WIDTH{1'b0}};
                pending_right <= 1'b1;
            end
        end else begin
            // 无效输入不移动窗口寄存器，也不产生输出窗口。
            p00       <= {PIXEL_WIDTH{1'b0}};
            p01       <= {PIXEL_WIDTH{1'b0}};
            p02       <= {PIXEL_WIDTH{1'b0}};
            p10       <= {PIXEL_WIDTH{1'b0}};
            p11       <= {PIXEL_WIDTH{1'b0}};
            p12       <= {PIXEL_WIDTH{1'b0}};
            p20       <= {PIXEL_WIDTH{1'b0}};
            p21       <= {PIXEL_WIDTH{1'b0}};
            p22       <= {PIXEL_WIDTH{1'b0}};
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
        end
    end

endmodule

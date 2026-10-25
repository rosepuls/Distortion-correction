`timescale 1ns / 1ps

// Trial Brown map applied after homography in ideal Q16.16 pixel space.
// k1=-1/4, k2=1/16, p1=1/32, p2=-1/32 and focal scale 512 reproduce
// Stage 7 arithmetic for integer inputs. These are not calibration results.
// Each arithmetic boundary is registered; the common advance signal holds
// every coordinate and metadata stage together under downstream backpressure.
module fractional_brown_mapper #(
    parameter integer CENTER_X = 640,
    parameter integer CENTER_Y = 360
) (
    input  wire                clk,
    input  wire                rstn,
    input  wire                s_valid,
    output wire                s_ready,
    input  wire signed [31:0]  s_sx,
    input  wire signed [31:0]  s_sy,
    input  wire                s_geometry_valid,
    input  wire [19:0]         s_pixel_id,
    input  wire [31:0]         s_frame_id,
    input  wire [15:0]         s_param_version,
    input  wire                s_sof,
    input  wire                s_eol,
    input  wire                s_eof,
    output reg                 m_valid,
    input  wire                m_ready,
    output reg signed [31:0]   m_sx,
    output reg signed [31:0]   m_sy,
    output reg                 m_geometry_valid,
    output reg [19:0]          m_pixel_id,
    output reg [31:0]          m_frame_id,
    output reg [15:0]          m_param_version,
    output reg                 m_sof,
    output reg                 m_eol,
    output reg                 m_eof
);
    localparam integer META_WIDTH = 71;
    localparam signed [32:0] MAX_DELTA = 33'sd134217728;
    wire advance = rstn && (!m_valid || m_ready);
    assign s_ready = advance;

    wire signed [32:0] dx_in = $signed({s_sx[31], s_sx}) -
        ($signed(CENTER_X) <<< 16);
    wire signed [32:0] dy_in = $signed({s_sy[31], s_sy}) -
        ($signed(CENTER_Y) <<< 16);
    wire input_in_range = dx_in >= -MAX_DELTA && dx_in <= MAX_DELTA &&
        dy_in >= -MAX_DELTA && dy_in <= MAX_DELTA;

    reg [7:0] valid_pipe;
    reg [META_WIDTH-1:0] meta [0:7];
    reg geometry [0:7];
    reg signed [31:0] x0, x1, x2, x3, x4, x5, x6;
    reg signed [31:0] y0, y1, y2, y3, y4, y5, y6;
    reg signed [32:0] dx0, dx1, dx2, dx3, dx4, dx5;
    reg signed [32:0] dy0, dy1, dy2, dy3, dy4, dy5;
    reg signed [63:0] xx1, yy1, xy1;
    reg signed [63:0] xx2, yy2, xy2, radius_sum2;
    reg signed [18:0] radius2_3, radius2_4;
    reg signed [37:0] radius4_4;
    reg signed [63:0] tang_x3, tang_y3;
    reg signed [63:0] tang_x4, tang_y4;
    reg signed [63:0] tang_x5, tang_y5;
    reg signed [63:0] tang_x6, tang_y6;
    reg signed [31:0] gain5;
    reg signed [63:0] radial_x6, radial_y6;
    reg signed [63:0] mapped_x7, mapped_y7;

    wire signed [63:0] xx_next = dx0 * dx0;
    wire signed [63:0] yy_next = dy0 * dy0;
    wire signed [63:0] xy_next = dx0 * dy0;
    wire signed [63:0] tang_x_next =
        ((xy2 <<< 1) - radius_sum2 - (xx2 <<< 1)) >>> 30;
    wire signed [63:0] tang_y_next =
        (radius_sum2 + (yy2 <<< 1) - (xy2 <<< 1)) >>> 30;
    wire signed [37:0] radius4_next =
        $signed(radius2_3) * $signed(radius2_3);
    wire signed [31:0] gain_next = (radius4_4 >>> 12) -
        ($signed(radius2_4) <<< 2);
    wire signed [63:0] radial_x_next =
        ($signed(dx5) * $signed(gain5)) >>> 16;
    wire signed [63:0] radial_y_next =
        ($signed(dy5) * $signed(gain5)) >>> 16;
    wire signed [63:0] mapped_x_next = $signed(x6) + radial_x6 + tang_x6;
    wire signed [63:0] mapped_y_next = $signed(y6) + radial_y6 + tang_y6;
    wire output_in_range = mapped_x7 >= -64'sd2147483648 &&
        mapped_x7 <= 64'sd2147483647 &&
        mapped_y7 >= -64'sd2147483648 &&
        mapped_y7 <= 64'sd2147483647;

    always @(posedge clk) begin
        if (!rstn) begin
            valid_pipe <= 8'b0;
            m_valid <= 1'b0;
            m_sx <= 0; m_sy <= 0; m_geometry_valid <= 0;
            m_pixel_id <= 0; m_frame_id <= 0; m_param_version <= 0;
            m_sof <= 0; m_eol <= 0; m_eof <= 0;
        end else if (advance) begin
            m_valid <= valid_pipe[7];
            if (valid_pipe[7]) begin
                m_sx <= output_in_range ? mapped_x7[31:0] : 32'sd0;
                m_sy <= output_in_range ? mapped_y7[31:0] : 32'sd0;
                m_geometry_valid <= geometry[7] && output_in_range;
                {m_pixel_id, m_frame_id, m_param_version, m_sof, m_eol, m_eof} <= meta[7];
            end

            valid_pipe <= {valid_pipe[6:0], s_valid};
            if (valid_pipe[6]) begin
                geometry[7] <= geometry[6];
                meta[7] <= meta[6];
                mapped_x7 <= mapped_x_next;
                mapped_y7 <= mapped_y_next;
            end
            if (valid_pipe[5]) begin
                geometry[6] <= geometry[5];
                meta[6] <= meta[5];
                x6 <= x5; y6 <= y5;
                tang_x6 <= tang_x5; tang_y6 <= tang_y5;
                radial_x6 <= radial_x_next;
                radial_y6 <= radial_y_next;
            end
            if (valid_pipe[4]) begin
                geometry[5] <= geometry[4];
                meta[5] <= meta[4];
                x5 <= x4; y5 <= y4;
                dx5 <= dx4; dy5 <= dy4;
                tang_x5 <= tang_x4; tang_y5 <= tang_y4;
                gain5 <= gain_next;
            end
            if (valid_pipe[3]) begin
                geometry[4] <= geometry[3];
                meta[4] <= meta[3];
                x4 <= x3; y4 <= y3;
                dx4 <= dx3; dy4 <= dy3;
                tang_x4 <= tang_x3; tang_y4 <= tang_y3;
                radius2_4 <= radius2_3;
                radius4_4 <= radius4_next;
            end
            if (valid_pipe[2]) begin
                geometry[3] <= geometry[2];
                meta[3] <= meta[2];
                x3 <= x2; y3 <= y2;
                dx3 <= dx2; dy3 <= dy2;
                radius2_3 <= radius_sum2 >>> 38;
                tang_x3 <= tang_x_next;
                tang_y3 <= tang_y_next;
            end
            if (valid_pipe[1]) begin
                geometry[2] <= geometry[1];
                meta[2] <= meta[1];
                x2 <= x1; y2 <= y1;
                dx2 <= dx1; dy2 <= dy1;
                xx2 <= xx1; yy2 <= yy1; xy2 <= xy1;
                radius_sum2 <= xx1 + yy1;
            end
            if (valid_pipe[0]) begin
                geometry[1] <= geometry[0];
                meta[1] <= meta[0];
                x1 <= x0; y1 <= y0;
                dx1 <= dx0; dy1 <= dy0;
                xx1 <= xx_next; yy1 <= yy_next; xy1 <= xy_next;
            end
            if (s_valid) begin
                geometry[0] <= s_geometry_valid && input_in_range;
                meta[0] <= {s_pixel_id, s_frame_id, s_param_version, s_sof, s_eol, s_eof};
                x0 <= input_in_range ? s_sx : 32'sd0;
                y0 <= input_in_range ? s_sy : 32'sd0;
                dx0 <= input_in_range ? dx_in : 33'sd0;
                dy0 <= input_in_range ? dy_in : 33'sd0;
            end
        end
    end
endmodule

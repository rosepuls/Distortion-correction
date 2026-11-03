`timescale 1ns / 1ps

// Stage 6 visual trial for a 120-degree barrel lens. This module retains the
// demo_radial_mapper interface so the two existing PDS projects can replace
// their mapper source without changing frame ownership or DDR wiring.
//
// Output-to-source Brown-Conrady map, with x=(u-CENTER_X)/512 and
// y=(v-CENTER_Y)/512:
//   k1=-1/4, k2=+1/16, p1=+1/32, p2=-1/32.
// These are deliberate visual trial values, not camera calibration data.
// Source coordinates are signed Q16.16. The actual center pixel stays fixed;
// all nearby pixels are remapped, including tangential asymmetry.
module demo_radial_mapper #(
    parameter integer CENTER_X = 640,
    parameter integer CENTER_Y = 360,
    parameter integer RADIAL_DENOM_SHIFT = 21
) (
    input  wire              clk,
    input  wire              rstn,
    input  wire              s_valid,
    output wire              s_ready,
    input  wire [10:0]       s_u,
    input  wire [9:0]        s_v,
    input  wire [19:0]       s_pixel_id,
    input  wire [31:0]       s_frame_id,
    input  wire [15:0]       s_param_version,
    input  wire              s_sof,
    input  wire              s_eol,
    input  wire              s_eof,
    output reg               m_valid,
    input  wire              m_ready,
    output reg signed [31:0] m_sx,
    output reg signed [31:0] m_sy,
    output reg               m_geometry_valid,
    output reg signed [31:0] m_j00,
    output reg signed [31:0] m_j01,
    output reg signed [31:0] m_j10,
    output reg signed [31:0] m_j11,
    output reg               m_j_valid,
    output reg [19:0]        m_pixel_id,
    output reg [31:0]        m_frame_id,
    output reg [15:0]        m_param_version,
    output reg               m_sof,
    output reg               m_eol,
    output reg               m_eof
);
    // All four registers advance together, including metadata, on a stall.
    wire advance = rstn && (!m_valid || m_ready);
    assign s_ready = advance;

    reg v0, v1, v2, v3;
    reg signed [12:0] dx0, dy0, dx1, dy1, dx2, dy2;
    reg [10:0] u0, u1, u2;
    reg [9:0] v0_coord, v1_coord, v2_coord;
    reg [21:0] r2_1;
    reg signed [25:0] xy1;
    reg [25:0] xx1, yy1;
    reg [15:0] radius2_q12;
    reg [31:0] radius4_q24;
    reg signed [31:0] tang_x_q16, tang_y_q16;
    reg signed [31:0] mapped_x3, mapped_y3;

    reg [19:0] id0, id1, id2, id3;
    reg [31:0] frame0, frame1, frame2, frame3;
    reg [15:0] version0, version1, version2, version3;
    reg sof0, sof1, sof2, sof3;
    reg eol0, eol1, eol2, eol3;
    reg eof0, eof1, eof2, eof3;

    wire signed [32:0] gain_delta_q16 =
        ($signed({1'b0, radius4_q24}) >>> 12) -
        ($signed({1'b0, radius2_q12}) <<< 2);
    wire signed [47:0] radial_x_q16 = $signed(dx2) * gain_delta_q16;
    wire signed [47:0] radial_y_q16 = $signed(dy2) * gain_delta_q16;
    wire signed [47:0] mapped_x_q16 =
        ($signed({1'b0, u2}) <<< 16) + radial_x_q16 + tang_x_q16;
    wire signed [47:0] mapped_y_q16 =
        ($signed({1'b0, v2_coord}) <<< 16) + radial_y_q16 + tang_y_q16;

    // With focal scale 512, p1=1/32 and p2=-1/32 make the Q16.16
    // tangential terms exactly four times these integer expressions.
    wire signed [31:0] tang_x_next =
        ((($signed(xy1) <<< 1) - $signed({1'b0, r2_1}) -
          ($signed({1'b0, xx1}) <<< 1)) <<< 2);
    wire signed [31:0] tang_y_next =
        (($signed({1'b0, r2_1}) +
          ($signed({1'b0, yy1}) <<< 1) -
          ($signed(xy1) <<< 1)) <<< 2);

    always @(posedge clk) begin
        if (!rstn) begin
            v0 <= 0; v1 <= 0; v2 <= 0; v3 <= 0; m_valid <= 0;
            m_sx <= 0; m_sy <= 0; m_geometry_valid <= 0;
            m_j00 <= 0; m_j01 <= 0; m_j10 <= 0; m_j11 <= 0;
            m_j_valid <= 0; m_pixel_id <= 0; m_frame_id <= 0;
            m_param_version <= 0; m_sof <= 0; m_eol <= 0; m_eof <= 0;
        end else if (advance) begin
            m_valid <= v3;
            if (v3) begin
                m_sx <= mapped_x3;
                m_sy <= mapped_y3;
                m_geometry_valid <= 1'b1;
                m_j00 <= 0; m_j01 <= 0; m_j10 <= 0; m_j11 <= 0;
                m_j_valid <= 0;
                m_pixel_id <= id3; m_frame_id <= frame3;
                m_param_version <= version3;
                m_sof <= sof3; m_eol <= eol3; m_eof <= eof3;
            end

            v3 <= v2;
            if (v2) begin
                mapped_x3 <= mapped_x_q16[31:0];
                mapped_y3 <= mapped_y_q16[31:0];
                id3 <= id2; frame3 <= frame2; version3 <= version2;
                sof3 <= sof2; eol3 <= eol2; eof3 <= eof2;
            end

            v2 <= v1;
            if (v1) begin
                dx2 <= dx1; dy2 <= dy1;
                u2 <= u1; v2_coord <= v1_coord;
                radius2_q12 <= r2_1 >> 6;
                radius4_q24 <= (r2_1 >> 6) * (r2_1 >> 6);
                tang_x_q16 <= tang_x_next;
                tang_y_q16 <= tang_y_next;
                id2 <= id1; frame2 <= frame1; version2 <= version1;
                sof2 <= sof1; eol2 <= eol1; eof2 <= eof1;
            end

            v1 <= v0;
            if (v0) begin
                dx1 <= dx0; dy1 <= dy0;
                u1 <= u0; v1_coord <= v0_coord;
                xx1 <= dx0 * dx0;
                yy1 <= dy0 * dy0;
                xy1 <= dx0 * dy0;
                r2_1 <= dx0 * dx0 + dy0 * dy0;
                id1 <= id0; frame1 <= frame0; version1 <= version0;
                sof1 <= sof0; eol1 <= eol0; eof1 <= eof0;
            end

            v0 <= s_valid;
            if (s_valid) begin
                dx0 <= $signed({1'b0, s_u}) - CENTER_X;
                dy0 <= $signed({2'b00, s_v}) - CENTER_Y;
                u0 <= s_u; v0_coord <= s_v;
                id0 <= s_pixel_id; frame0 <= s_frame_id;
                version0 <= s_param_version;
                sof0 <= s_sof; eol0 <= s_eol; eof0 <= s_eof;
            end
        end
    end
endmodule

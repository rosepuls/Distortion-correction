`timescale 1ns / 1ps

// Fixed radial mapper used by the Stage 4 on-board algorithm demonstration.
// It implements source = output + (output-center)*r^2/2^23.  The arithmetic
// output is signed Q16.16; image-border handling remains in the sampler.
module demo_radial_mapper #(
    parameter integer CENTER_X = 640,
    parameter integer CENTER_Y = 360,
    parameter integer RADIAL_DENOM_SHIFT = 23
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
    localparam integer DELTA_SHIFT = RADIAL_DENOM_SHIFT - 16;

    reg stage0_valid;
    reg signed [12:0] stage0_dx;
    reg signed [12:0] stage0_dy;
    reg [10:0] stage0_u;
    reg [9:0] stage0_v;
    reg [19:0] stage0_pixel_id;
    reg [31:0] stage0_frame_id;
    reg [15:0] stage0_param_version;
    reg stage0_sof, stage0_eol, stage0_eof;

    reg stage1_valid;
    reg signed [12:0] stage1_dx;
    reg signed [12:0] stage1_dy;
    reg [21:0] stage1_r2;
    reg [10:0] stage1_u;
    reg [9:0] stage1_v;
    reg [19:0] stage1_pixel_id;
    reg [31:0] stage1_frame_id;
    reg [15:0] stage1_param_version;
    reg stage1_sof, stage1_eol, stage1_eof;

    wire pipeline_advance = rstn && (~m_valid || m_ready);
    assign s_ready = pipeline_advance;

    wire signed [47:0] radial_x_product =
        $signed(stage1_dx) * $signed({1'b0, stage1_r2});
    wire signed [47:0] radial_y_product =
        $signed(stage1_dy) * $signed({1'b0, stage1_r2});
    wire signed [47:0] base_x_q16 = $signed({1'b0, stage1_u, 16'd0});
    wire signed [47:0] base_y_q16 = $signed({1'b0, stage1_v, 16'd0});
    wire signed [47:0] mapped_x_q16 =
        base_x_q16 + (radial_x_product >>> DELTA_SHIFT);
    wire signed [47:0] mapped_y_q16 =
        base_y_q16 + (radial_y_product >>> DELTA_SHIFT);

    always @(posedge clk) begin
        if (!rstn) begin
            stage0_valid <= 1'b0;
            stage1_valid <= 1'b0;
            m_valid <= 1'b0;
            m_sx <= 0; m_sy <= 0; m_geometry_valid <= 0;
            m_j00 <= 0; m_j01 <= 0; m_j10 <= 0; m_j11 <= 0; m_j_valid <= 0;
            m_pixel_id <= 0; m_frame_id <= 0; m_param_version <= 0;
            m_sof <= 0; m_eol <= 0; m_eof <= 0;
            stage0_dx <= 0; stage0_dy <= 0; stage0_u <= 0; stage0_v <= 0;
            stage0_pixel_id <= 0; stage0_frame_id <= 0; stage0_param_version <= 0;
            stage0_sof <= 0; stage0_eol <= 0; stage0_eof <= 0;
            stage1_dx <= 0; stage1_dy <= 0; stage1_r2 <= 0;
            stage1_u <= 0; stage1_v <= 0; stage1_pixel_id <= 0;
            stage1_frame_id <= 0; stage1_param_version <= 0;
            stage1_sof <= 0; stage1_eol <= 0; stage1_eof <= 0;
        end else if (pipeline_advance) begin
            m_valid <= stage1_valid;
            if (stage1_valid) begin
                m_sx <= mapped_x_q16[31:0];
                m_sy <= mapped_y_q16[31:0];
                m_geometry_valid <= 1'b1;
                m_j00 <= 0; m_j01 <= 0; m_j10 <= 0; m_j11 <= 0;
                m_j_valid <= 1'b0;
                m_pixel_id <= stage1_pixel_id;
                m_frame_id <= stage1_frame_id;
                m_param_version <= stage1_param_version;
                m_sof <= stage1_sof; m_eol <= stage1_eol; m_eof <= stage1_eof;
            end

            stage1_valid <= stage0_valid;
            if (stage0_valid) begin
                stage1_dx <= stage0_dx;
                stage1_dy <= stage0_dy;
                stage1_r2 <= stage0_dx * stage0_dx + stage0_dy * stage0_dy;
                stage1_u <= stage0_u; stage1_v <= stage0_v;
                stage1_pixel_id <= stage0_pixel_id;
                stage1_frame_id <= stage0_frame_id;
                stage1_param_version <= stage0_param_version;
                stage1_sof <= stage0_sof; stage1_eol <= stage0_eol; stage1_eof <= stage0_eof;
            end

            stage0_valid <= s_valid;
            if (s_valid) begin
                stage0_dx <= $signed({1'b0, s_u}) - CENTER_X;
                stage0_dy <= $signed({2'b00, s_v}) - CENTER_Y;
                stage0_u <= s_u; stage0_v <= s_v;
                stage0_pixel_id <= s_pixel_id;
                stage0_frame_id <= s_frame_id;
                stage0_param_version <= s_param_version;
                stage0_sof <= s_sof; stage0_eol <= s_eol; stage0_eof <= s_eof;
            end
        end
    end
endmodule

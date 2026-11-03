`timescale 1ns / 1ps

// Center-aligned 3:2 upscaling coordinate mapper. Input u/v are output
// coordinates. Source coordinates use signed Q16.16 so the first output row
// and column can represent the half-pixel border footprint.
module scale_3_2_mapper (
    input  wire               clk,
    input  wire               rstn,
    input  wire               s_valid,
    output wire               s_ready,
    input  wire [11:0]        s_u,
    input  wire [11:0]        s_v,
    input  wire [20:0]        s_pixel_id,
    input  wire [31:0]        s_frame_id,
    input  wire [15:0]        s_param_version,
    input  wire               s_sof,
    input  wire               s_eol,
    input  wire               s_eof,
    output reg                m_valid,
    input  wire               m_ready,
    output reg signed [31:0]  m_sx,
    output reg signed [31:0]  m_sy,
    output reg                m_geometry_valid,
    output reg [20:0]         m_pixel_id,
    output reg [31:0]         m_frame_id,
    output reg [15:0]         m_param_version,
    output reg                m_sof,
    output reg                m_eol,
    output reg                m_eof
);
    wire signed [31:0] x_q16 = map_coord(s_u);
    wire signed [31:0] y_q16 = map_coord(s_v);

    // floor(coord/3) using the exact 12-bit reciprocal multiply
    // floor(coord * 43691 / 2^17). The three residual phases correspond to
    // src positions -1/6, 1/2 and 7/6, expressed as rounded Q16.16 values.
    function automatic signed [31:0] map_coord;
        input [11:0] coord;
        reg [27:0] quotient_product;
        reg [10:0] quotient;
        reg [1:0] phase;
        reg signed [31:0] base_q16;
        begin
            quotient_product = coord * 16'd43691;
            quotient = quotient_product[27:17];
            phase = coord - (quotient * 3);
            base_q16 = $signed({4'd0, quotient, 1'b0, 16'd0});
            case (phase)
                2'd0: map_coord = base_q16 - 32'sd10923;
                2'd1: map_coord = base_q16 + 32'sd32768;
                default: map_coord = base_q16 + 32'sd76459;
            endcase
        end
    endfunction

    assign s_ready = rstn && (!m_valid || m_ready);

    always @(posedge clk) begin
        if (!rstn) begin
            m_valid <= 1'b0;
            m_sx <= 32'sd0;
            m_sy <= 32'sd0;
            m_geometry_valid <= 1'b0;
            m_pixel_id <= 21'd0;
            m_frame_id <= 32'd0;
            m_param_version <= 16'd0;
            m_sof <= 1'b0;
            m_eol <= 1'b0;
            m_eof <= 1'b0;
        end else if (s_ready) begin
            m_valid <= s_valid;
            if (s_valid) begin
                m_sx <= x_q16;
                m_sy <= y_q16;
                m_geometry_valid <= (s_u < 12'd1920) && (s_v < 12'd1080);
                m_pixel_id <= s_pixel_id;
                m_frame_id <= s_frame_id;
                m_param_version <= s_param_version;
                m_sof <= s_sof;
                m_eol <= s_eol;
                m_eof <= s_eof;
            end
        end
    end
endmodule

`timescale 1ns / 1ps

module identity_mapper (
    input  wire               clk,
    input  wire               rstn,

    input  wire               s_valid,
    output wire               s_ready,
    input  wire [10:0]        s_u,
    input  wire [10:0]        s_v,
    input  wire [19:0]        s_pixel_id,
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
    output reg signed [31:0]  m_j00,
    output reg signed [31:0]  m_j01,
    output reg signed [31:0]  m_j10,
    output reg signed [31:0]  m_j11,
    output reg                m_j_valid,
    output reg [19:0]         m_pixel_id,
    output reg [31:0]         m_frame_id,
    output reg [15:0]         m_param_version,
    output reg                m_sof,
    output reg                m_eol,
    output reg                m_eof
);

    // One elastic register accepts a new coordinate when it is empty or when
    // the current coordinate is consumed on this clock edge.
    assign s_ready = rstn && (~m_valid || m_ready);

    always @(posedge clk) begin
        if (!rstn) begin
            m_valid          <= 1'b0;
            m_sx             <= 32'sd0;
            m_sy             <= 32'sd0;
            m_geometry_valid <= 1'b0;
            m_j00            <= 32'sd0;
            m_j01            <= 32'sd0;
            m_j10            <= 32'sd0;
            m_j11            <= 32'sd0;
            m_j_valid        <= 1'b0;
            m_pixel_id       <= 20'd0;
            m_frame_id       <= 32'd0;
            m_param_version  <= 16'd0;
            m_sof            <= 1'b0;
            m_eol            <= 1'b0;
            m_eof            <= 1'b0;
        end else if (s_ready) begin
            m_valid <= s_valid;
            if (s_valid) begin
                // u and v are non-negative integer pixel-center coordinates.
                // Zero extension followed by 16 zero fraction bits produces
                // the signed public Q16.16 representation without arithmetic.
                m_sx             <= $signed({5'd0, s_u, 16'd0});
                m_sy             <= $signed({6'd0, s_v, 16'd0});
                m_geometry_valid <= 1'b1;
                // The identity mapping has the exact Jacobian [[1,0],[0,1]].
                // All four public derivative elements use signed Q16.16.
                m_j00            <= 32'sh00010000;
                m_j01            <= 32'sd0;
                m_j10            <= 32'sd0;
                m_j11            <= 32'sh00010000;
                m_j_valid        <= 1'b1;
                m_pixel_id       <= s_pixel_id;
                m_frame_id       <= s_frame_id;
                m_param_version  <= s_param_version;
                m_sof            <= s_sof;
                m_eol            <= s_eol;
                m_eof            <= s_eof;
            end
        end
    end

endmodule

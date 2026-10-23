`timescale 1ns / 1ps

module bilinear_interpolator (
    input  wire         clk,
    input  wire         rstn,

    input  wire         s_valid,
    output wire         s_ready,
    input  wire [31:0]  s_p00,
    input  wire [31:0]  s_p10,
    input  wire [31:0]  s_p01,
    input  wire [31:0]  s_p11,
    input  wire [15:0]  s_fx,
    input  wire [15:0]  s_fy,
    input  wire [3:0]   s_neighbor_valid,
    input  wire         s_geometry_valid,
    input  wire [19:0]  s_pixel_id,
    input  wire [31:0]  s_frame_id,
    input  wire [15:0]  s_param_version,
    input  wire         s_sof,
    input  wire         s_eol,
    input  wire         s_eof,

    output reg          m_valid,
    input  wire         m_ready,
    output reg [31:0]   m_pixel,
    output reg          m_geometry_valid,
    output reg [19:0]   m_pixel_id,
    output reg [31:0]   m_frame_id,
    output reg [15:0]   m_param_version,
    output reg          m_sof,
    output reg          m_eol,
    output reg          m_eof
);

    function automatic [7:0] interpolate_channel;
        input [7:0] p00;
        input [7:0] p10;
        input [7:0] p01;
        input [7:0] p11;
        input [3:0] valid_mask;
        input [15:0] fx_value;
        input [15:0] fy_value;
        reg [7:0] c00;
        reg [7:0] c10;
        reg [7:0] c01;
        reg [7:0] c11;
        reg [16:0] wx0;
        reg [16:0] wy0;
        reg [24:0] top;
        reg [24:0] bottom;
        reg [41:0] accumulated;
        begin
            c00 = valid_mask[0] ? p00 : 8'd0;
            c10 = valid_mask[1] ? p10 : 8'd0;
            c01 = valid_mask[2] ? p01 : 8'd0;
            c11 = valid_mask[3] ? p11 : 8'd0;
            wx0 = 17'h10000 - {1'b0, fx_value};
            wy0 = 17'h10000 - {1'b0, fy_value};
            top = c00 * wx0 + c10 * {1'b0, fx_value};
            bottom = c01 * wx0 + c11 * {1'b0, fx_value};
            accumulated = top * wy0 + bottom * {1'b0, fy_value};
            // Q0.32 to integer, rounded to nearest with half values upward.
            interpolate_channel = (accumulated + 42'd2147483648) >> 32;
        end
    endfunction

    assign s_ready = rstn && (~m_valid || m_ready);

    always @(posedge clk) begin
        if (!rstn) begin
            m_valid          <= 1'b0;
            m_pixel          <= 32'd0;
            m_geometry_valid <= 1'b0;
            m_pixel_id       <= 20'd0;
            m_frame_id       <= 32'd0;
            m_param_version  <= 16'd0;
            m_sof            <= 1'b0;
            m_eol            <= 1'b0;
            m_eof            <= 1'b0;
        end else if (s_ready) begin
            m_valid <= s_valid;
            if (s_valid) begin
                m_pixel[31:24] <= interpolate_channel(
                    s_p00[31:24], s_p10[31:24], s_p01[31:24], s_p11[31:24],
                    s_neighbor_valid, s_fx, s_fy);
                m_pixel[23:16] <= interpolate_channel(
                    s_p00[23:16], s_p10[23:16], s_p01[23:16], s_p11[23:16],
                    s_neighbor_valid, s_fx, s_fy);
                m_pixel[15:8] <= interpolate_channel(
                    s_p00[15:8], s_p10[15:8], s_p01[15:8], s_p11[15:8],
                    s_neighbor_valid, s_fx, s_fy);
                m_pixel[7:0]      <= 8'h00;
                m_geometry_valid  <= s_geometry_valid;
                m_pixel_id        <= s_pixel_id;
                m_frame_id        <= s_frame_id;
                m_param_version   <= s_param_version;
                m_sof             <= s_sof;
                m_eol             <= s_eol;
                m_eof             <= s_eof;
            end
        end
    end

endmodule

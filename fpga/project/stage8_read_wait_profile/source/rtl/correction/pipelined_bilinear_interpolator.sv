`timescale 1ns / 1ps

// Three elastic stages keep the cache read mux and the two multiply levels
// out of the same 125 MHz timing path. Arithmetic and rounding match
// bilinear_interpolator exactly; RGBX's low byte is always zero.
module pipelined_bilinear_interpolator (
    input  wire         clk,
    input  wire         rstn,
    input  wire         s_valid,
    output wire         s_ready,
    input  wire [31:0]  s_p00, s_p10, s_p01, s_p11,
    input  wire [15:0]  s_fx, s_fy,
    input  wire [3:0]   s_neighbor_valid,
    input  wire         s_geometry_valid,
    input  wire [19:0]  s_pixel_id,
    input  wire [31:0]  s_frame_id,
    input  wire [15:0]  s_param_version,
    input  wire         s_sof, s_eol, s_eof,
    output reg          m_valid,
    input  wire         m_ready,
    output reg [31:0]   m_pixel,
    output reg          m_geometry_valid,
    output reg [19:0]   m_pixel_id,
    output reg [31:0]   m_frame_id,
    output reg [15:0]   m_param_version,
    output reg          m_sof, m_eol, m_eof
);
    reg v0, v1;
    wire r2 = !m_valid || m_ready;
    wire r1 = !v1 || r2;
    wire r0 = !v0 || r1;
    assign s_ready = rstn && r0;

    reg [31:0] p00_0, p10_0, p01_0, p11_0;
    reg [15:0] fx_0, fy_0;
    reg [3:0] mask_0;
    reg geo_0, sof_0, eol_0, eof_0;
    reg [19:0] id_0;
    reg [31:0] frame_0;
    reg [15:0] version_0;

    reg [24:0] top_r, top_g, top_b, bottom_r, bottom_g, bottom_b;
    reg [15:0] fy_1;
    reg geo_1, sof_1, eol_1, eof_1;
    reg [19:0] id_1;
    reg [31:0] frame_1;
    reg [15:0] version_1;

    wire [16:0] wx0 = 17'h10000 - {1'b0, fx_0};
    wire [16:0] wy0 = 17'h10000 - {1'b0, fy_1};
    wire [7:0] r00 = mask_0[0] ? p00_0[31:24] : 8'd0;
    wire [7:0] r10 = mask_0[1] ? p10_0[31:24] : 8'd0;
    wire [7:0] r01 = mask_0[2] ? p01_0[31:24] : 8'd0;
    wire [7:0] r11 = mask_0[3] ? p11_0[31:24] : 8'd0;
    wire [7:0] g00 = mask_0[0] ? p00_0[23:16] : 8'd0;
    wire [7:0] g10 = mask_0[1] ? p10_0[23:16] : 8'd0;
    wire [7:0] g01 = mask_0[2] ? p01_0[23:16] : 8'd0;
    wire [7:0] g11 = mask_0[3] ? p11_0[23:16] : 8'd0;
    wire [7:0] b00 = mask_0[0] ? p00_0[15:8] : 8'd0;
    wire [7:0] b10 = mask_0[1] ? p10_0[15:8] : 8'd0;
    wire [7:0] b01 = mask_0[2] ? p01_0[15:8] : 8'd0;
    wire [7:0] b11 = mask_0[3] ? p11_0[15:8] : 8'd0;

    wire [41:0] sum_r = top_r * wy0 + bottom_r * {1'b0, fy_1};
    wire [41:0] sum_g = top_g * wy0 + bottom_g * {1'b0, fy_1};
    wire [41:0] sum_b = top_b * wy0 + bottom_b * {1'b0, fy_1};
    wire [41:0] rounded_r = sum_r + 42'd2147483648;
    wire [41:0] rounded_g = sum_g + 42'd2147483648;
    wire [41:0] rounded_b = sum_b + 42'd2147483648;

    always @(posedge clk) begin
        if (!rstn) begin
            v0 <= 1'b0;
            v1 <= 1'b0;
            m_valid <= 1'b0;
            m_pixel <= 32'd0;
            m_geometry_valid <= 1'b0;
            m_pixel_id <= 20'd0;
            m_frame_id <= 32'd0;
            m_param_version <= 16'd0;
            m_sof <= 1'b0;
            m_eol <= 1'b0;
            m_eof <= 1'b0;
        end else begin
            if (r0) begin
                v0 <= s_valid;
                if (s_valid) begin
                    p00_0 <= s_p00; p10_0 <= s_p10;
                    p01_0 <= s_p01; p11_0 <= s_p11;
                    fx_0 <= s_fx; fy_0 <= s_fy;
                    mask_0 <= s_neighbor_valid;
                    geo_0 <= s_geometry_valid;
                    id_0 <= s_pixel_id; frame_0 <= s_frame_id;
                    version_0 <= s_param_version;
                    sof_0 <= s_sof; eol_0 <= s_eol; eof_0 <= s_eof;
                end
            end
            if (r1) begin
                v1 <= v0;
                if (v0) begin
                    top_r <= r00 * wx0 + r10 * {1'b0, fx_0};
                    top_g <= g00 * wx0 + g10 * {1'b0, fx_0};
                    top_b <= b00 * wx0 + b10 * {1'b0, fx_0};
                    bottom_r <= r01 * wx0 + r11 * {1'b0, fx_0};
                    bottom_g <= g01 * wx0 + g11 * {1'b0, fx_0};
                    bottom_b <= b01 * wx0 + b11 * {1'b0, fx_0};
                    fy_1 <= fy_0;
                    geo_1 <= geo_0;
                    id_1 <= id_0; frame_1 <= frame_0;
                    version_1 <= version_0;
                    sof_1 <= sof_0; eol_1 <= eol_0; eof_1 <= eof_0;
                end
            end
            if (r2) begin
                m_valid <= v1;
                if (v1) begin
                    m_pixel <= {rounded_r[39:32], rounded_g[39:32],
                                rounded_b[39:32], 8'h00};
                    m_geometry_valid <= geo_1;
                    m_pixel_id <= id_1; m_frame_id <= frame_1;
                    m_param_version <= version_1;
                    m_sof <= sof_1; m_eol <= eol_1; m_eof <= eof_1;
                end
            end
        end
    end
endmodule

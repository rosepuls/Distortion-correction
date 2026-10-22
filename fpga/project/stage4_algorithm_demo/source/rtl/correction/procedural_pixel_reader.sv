`timescale 1ns / 1ps

// Board-independent stand-in for the future DDR Tile Cache.  It evaluates a
// deterministic RGBX8888 grid/gradient at four integer source coordinates.
module procedural_pixel_reader #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720
) (
    input  wire         clk,
    input  wire         rstn,
    input  wire         s_valid,
    output wire         s_ready,
    input  wire [10:0]  s_x0,
    input  wire [10:0]  s_x1,
    input  wire [9:0]   s_y0,
    input  wire [9:0]   s_y1,
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
    output reg [31:0]   m_p00,
    output reg [31:0]   m_p10,
    output reg [31:0]   m_p01,
    output reg [31:0]   m_p11,
    output reg [15:0]   m_fx,
    output reg [15:0]   m_fy,
    output reg [3:0]    m_neighbor_valid,
    output reg          m_geometry_valid,
    output reg [19:0]   m_pixel_id,
    output reg [31:0]   m_frame_id,
    output reg [15:0]   m_param_version,
    output reg          m_sof,
    output reg          m_eol,
    output reg          m_eof
);

    function automatic [31:0] pattern_pixel;
        input [10:0] x;
        input [9:0] y;
        begin
            if ((x[5:0] == 6'd0) || (y[5:0] == 6'd0) ||
                (x == IMAGE_WIDTH - 1) || (y == IMAGE_HEIGHT - 1))
                pattern_pixel = 32'hffffff00;
            else
                pattern_pixel = {x[7:0], y[7:0], x[7:0] ^ y[7:0], 8'h00};
        end
    endfunction

    assign s_ready = rstn && (~m_valid || m_ready);

    always @(posedge clk) begin
        if (!rstn) begin
            m_valid          <= 1'b0;
            m_p00            <= 32'd0;
            m_p10            <= 32'd0;
            m_p01            <= 32'd0;
            m_p11            <= 32'd0;
            m_fx             <= 16'd0;
            m_fy             <= 16'd0;
            m_neighbor_valid <= 4'd0;
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
                m_p00 <= s_neighbor_valid[0] ? pattern_pixel(s_x0, s_y0) : 32'd0;
                m_p10 <= s_neighbor_valid[1] ? pattern_pixel(s_x1, s_y0) : 32'd0;
                m_p01 <= s_neighbor_valid[2] ? pattern_pixel(s_x0, s_y1) : 32'd0;
                m_p11 <= s_neighbor_valid[3] ? pattern_pixel(s_x1, s_y1) : 32'd0;
                m_fx             <= s_fx;
                m_fy             <= s_fy;
                m_neighbor_valid <= s_neighbor_valid;
                m_geometry_valid <= s_geometry_valid;
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

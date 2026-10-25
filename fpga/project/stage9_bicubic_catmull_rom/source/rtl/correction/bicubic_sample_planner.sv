`timescale 1ns / 1ps

module bicubic_sample_planner #(
    parameter integer IMAGE_WIDTH  = 1280,
    parameter integer IMAGE_HEIGHT = 720
) (
    input  wire               clk,
    input  wire               rstn,
    input  wire               s_valid,
    output wire               s_ready,
    input  wire signed [31:0] s_sx,
    input  wire signed [31:0] s_sy,
    input  wire               s_geometry_valid,
    input  wire [19:0]        s_pixel_id,
    input  wire [31:0]        s_frame_id,
    input  wire [15:0]        s_param_version,
    input  wire               s_sof,
    input  wire               s_eol,
    input  wire               s_eof,
    output reg                m_valid,
    input  wire               m_ready,
    output reg [10:0]         m_x0,
    output reg [10:0]         m_x1,
    output reg [10:0]         m_x2,
    output reg [10:0]         m_x3,
    output reg [9:0]          m_y0,
    output reg [9:0]          m_y1,
    output reg [9:0]          m_y2,
    output reg [9:0]          m_y3,
    output reg [15:0]         m_fx,
    output reg [15:0]         m_fy,
    output reg [15:0]         m_neighbor_valid,
    output reg                m_geometry_valid,
    output reg [19:0]         m_pixel_id,
    output reg [31:0]         m_frame_id,
    output reg [15:0]         m_param_version,
    output reg                m_sof,
    output reg                m_eol,
    output reg                m_eof
);
    wire signed [31:0] x_floor = s_sx >>> 16;
    wire signed [31:0] y_floor = s_sy >>> 16;
    wire signed [31:0] x0 = x_floor - 32'sd1;
    wire signed [31:0] x1 = x_floor;
    wire signed [31:0] x2 = x_floor + 32'sd1;
    wire signed [31:0] x3 = x_floor + 32'sd2;
    wire signed [31:0] y0 = y_floor - 32'sd1;
    wire signed [31:0] y1 = y_floor;
    wire signed [31:0] y2 = y_floor + 32'sd1;
    wire signed [31:0] y3 = y_floor + 32'sd2;

    wire all_neighbors_in_bounds =
        (x0 >= 0 && x3 < IMAGE_WIDTH &&
         y0 >= 0 && y3 < IMAGE_HEIGHT);

    function automatic [10:0] clamp_x;
        input signed [31:0] coordinate;
        begin
            if (coordinate < 0)
                clamp_x = 11'd0;
            else if (coordinate >= IMAGE_WIDTH)
                clamp_x = IMAGE_WIDTH - 1;
            else
                clamp_x = coordinate[10:0];
        end
    endfunction

    function automatic [9:0] clamp_y;
        input signed [31:0] coordinate;
        begin
            if (coordinate < 0)
                clamp_y = 10'd0;
            else if (coordinate >= IMAGE_HEIGHT)
                clamp_y = IMAGE_HEIGHT - 1;
            else
                clamp_y = coordinate[9:0];
        end
    endfunction

    assign s_ready = rstn && (!m_valid || m_ready);

    always @(posedge clk) begin
        if (!rstn) begin
            m_valid <= 1'b0;
            m_x0 <= 11'd0; m_x1 <= 11'd0;
            m_x2 <= 11'd0; m_x3 <= 11'd0;
            m_y0 <= 10'd0; m_y1 <= 10'd0;
            m_y2 <= 10'd0; m_y3 <= 10'd0;
            m_fx <= 16'd0; m_fy <= 16'd0;
            m_neighbor_valid <= 16'd0;
            m_geometry_valid <= 1'b0;
            m_pixel_id <= 20'd0; m_frame_id <= 32'd0;
            m_param_version <= 16'd0;
            m_sof <= 1'b0; m_eol <= 1'b0; m_eof <= 1'b0;
        end else if (s_ready) begin
            m_valid <= s_valid;
            if (s_valid) begin
                m_x0 <= clamp_x(x0); m_x1 <= clamp_x(x1);
                m_x2 <= clamp_x(x2); m_x3 <= clamp_x(x3);
                m_y0 <= clamp_y(y0); m_y1 <= clamp_y(y1);
                m_y2 <= clamp_y(y2); m_y3 <= clamp_y(y3);
                m_fx <= s_sx[15:0]; m_fy <= s_sy[15:0];
                m_geometry_valid <= s_geometry_valid && all_neighbors_in_bounds;
                m_neighbor_valid <= (s_geometry_valid && all_neighbors_in_bounds)
                    ? 16'hffff : 16'h0000;
                m_pixel_id <= s_pixel_id; m_frame_id <= s_frame_id;
                m_param_version <= s_param_version;
                m_sof <= s_sof; m_eol <= s_eol; m_eof <= s_eof;
            end
        end
    end
endmodule

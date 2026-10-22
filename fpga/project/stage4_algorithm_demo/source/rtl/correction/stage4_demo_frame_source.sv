`timescale 1ns / 1ps

// Converts an HDMI active-video window into ordered Stage 4 demo requests.
// The downstream result is delayed but retains exactly one transaction for
// every active input pixel, including black pixels outside the mapped source.
module stage4_demo_frame_source #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer FIFO_DEPTH = 16,
    parameter integer LEVEL_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH + 1)
) (
    input  wire         clk,
    input  wire         rstn,
    input  wire         frame_sync,
    input  wire         active_video,
    output wire         pixel_valid,
    output wire [31:0]  pixel,
    output wire [19:0]  pixel_id,
    output wire         frame_complete,
    output reg          input_stall,
    output reg          sequence_error
);
    reg frame_sync_d;
    reg [10:0] scan_x;
    reg [9:0] scan_y;
    reg [19:0] scan_pixel_id;
    reg [31:0] frame_id;
    reg [19:0] expected_output_id;

    wire pipeline_ready;
    wire output_geometry_valid;
    wire [31:0] output_frame_id;
    wire [15:0] output_param_version;
    wire output_sof, output_eol, output_eof;
    wire [LEVEL_WIDTH-1:0] unused_fifo_level;
    wire input_fire = active_video && pipeline_ready;
    wire frame_sync_rise = frame_sync && !frame_sync_d;

    stage4_demo_pipeline #(
        .IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
        .FIFO_DEPTH(FIFO_DEPTH),.LEVEL_WIDTH(LEVEL_WIDTH),.BORDER_REPLICATE(0)
    ) pipeline (
        .clk(clk),.rstn(rstn),.s_valid(active_video),.s_ready(pipeline_ready),
        .s_u(scan_x),.s_v(scan_y),.s_pixel_id(scan_pixel_id),.s_frame_id(frame_id),
        .s_param_version(16'hd004),.s_sof(scan_pixel_id==0),
        .s_eol(scan_x==IMAGE_WIDTH-1),.s_eof(scan_pixel_id==IMAGE_WIDTH*IMAGE_HEIGHT-1),
        .m_valid(pixel_valid),.m_ready(1'b1),.m_pixel(pixel),
        .m_geometry_valid(output_geometry_valid),.m_pixel_id(pixel_id),
        .m_frame_id(output_frame_id),.m_param_version(output_param_version),
        .m_sof(output_sof),.m_eol(output_eol),.m_eof(output_eof),
        .fifo_level(unused_fifo_level)
    );

    assign frame_complete = pixel_valid && output_eof;

    always @(posedge clk) begin
        if (!rstn) begin
            frame_sync_d <= 1'b0;
            scan_x <= 0;
            scan_y <= 0;
            scan_pixel_id <= 0;
            frame_id <= 0;
            expected_output_id <= 0;
            input_stall <= 1'b0;
            sequence_error <= 1'b0;
        end else begin
            frame_sync_d <= frame_sync;
            if (frame_sync_rise) begin
                scan_x <= 0;
                scan_y <= 0;
                scan_pixel_id <= 0;
                frame_id <= frame_id + 1'b1;
                expected_output_id <= 0;
            end else if (input_fire) begin
                if (scan_x == IMAGE_WIDTH-1) begin
                    scan_x <= 0;
                    if (scan_y == IMAGE_HEIGHT-1)
                        scan_y <= 0;
                    else
                        scan_y <= scan_y + 1'b1;
                end else begin
                    scan_x <= scan_x + 1'b1;
                end
                if (scan_pixel_id == IMAGE_WIDTH*IMAGE_HEIGHT-1)
                    scan_pixel_id <= 0;
                else
                    scan_pixel_id <= scan_pixel_id + 1'b1;
            end

            if (active_video && !pipeline_ready)
                input_stall <= 1'b1;

            if (pixel_valid) begin
                if (pixel_id != expected_output_id)
                    sequence_error <= 1'b1;
                if (output_eof)
                    expected_output_id <= 0;
                else
                    expected_output_id <= expected_output_id + 1'b1;
            end
        end
    end
endmodule

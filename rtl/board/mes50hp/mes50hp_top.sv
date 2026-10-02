`timescale 1ns/1ps

// Synthesizable PGL50H algorithm-system top.
//
// The memory interface is a logical RGB888 pixel request/response boundary.
// A later MES50HP DDR3 adapter must translate pixel indexes to the vendor IP
// interface.  The output stream is not backpressured and must be consumed
// whenever out_valid is asserted.
module mes50hp_top #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer COORD_WIDTH = 13,
    parameter integer ADDR_WIDTH = 32
) (
    input  wire                         clk,
    input  wire                         reset_n,
    input  wire                         frame_start,
    output reg                          frame_busy,
    output wire                         frame_done,

    input  wire signed [31:0]           cfg_fx_q19,
    input  wire signed [31:0]           cfg_fy_q19,
    input  wire signed [31:0]           cfg_cx_q19,
    input  wire signed [31:0]           cfg_cy_q19,
    input  wire signed [31:0]           cfg_inv_fx_q30,
    input  wire signed [31:0]           cfg_inv_fy_q30,
    input  wire signed [31:0]           cfg_k1_q28,
    input  wire signed [31:0]           cfg_k2_q28,
    input  wire signed [31:0]           cfg_p1_q28,
    input  wire signed [31:0]           cfg_p2_q28,

    output wire                         mem_req_valid,
    input  wire                         mem_req_ready,
    output wire [ADDR_WIDTH-1:0]        mem_req_addr,
    input  wire                         mem_rsp_valid,
    output wire                         mem_rsp_ready,
    input  wire [23:0]                  mem_rsp_data,

    output wire [23:0]                  out_pixel,
    output wire                         out_valid,
    output wire                         out_sof,
    output wire                         out_eol
);
    wire core_rst_n;
    reg [COORD_WIDTH-1:0] scan_x;
    reg [COORD_WIDTH-1:0] scan_y;
    reg [COORD_WIDTH-1:0] output_y;
    reg all_pixels_issued;

    wire pipeline_in_ready;
    wire pipeline_in_valid;
    wire pipeline_in_sof;
    wire pipeline_in_eol;
    wire pipeline_input_accept;

    localparam [COORD_WIDTH-1:0] LAST_X = IMAGE_WIDTH - 1;
    localparam [COORD_WIDTH-1:0] LAST_Y = IMAGE_HEIGHT - 1;

    mes50hp_reset_sync reset_sync_inst (
        .clk(clk),
        .reset_n(reset_n),
        .rst_n(core_rst_n)
    );

    assign pipeline_in_valid = frame_busy && !all_pixels_issued;
    assign pipeline_in_sof = (scan_x == {COORD_WIDTH{1'b0}}) &&
                             (scan_y == {COORD_WIDTH{1'b0}});
    assign pipeline_in_eol = (scan_x == LAST_X);
    assign pipeline_input_accept = pipeline_in_valid && pipeline_in_ready;
    assign frame_done = frame_busy && out_valid && out_eol && (output_y == LAST_Y);

    distortion_image_pipeline #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .COORD_WIDTH(COORD_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .USE_OPTIMIZED_CORE(1)
    ) pipeline_inst (
        .clk(clk),
        .rst_n(core_rst_n),
        .in_valid(pipeline_in_valid),
        .in_sof(pipeline_in_sof),
        .in_eol(pipeline_in_eol),
        .in_ready(pipeline_in_ready),
        .cfg_fx_q19(cfg_fx_q19),
        .cfg_fy_q19(cfg_fy_q19),
        .cfg_cx_q19(cfg_cx_q19),
        .cfg_cy_q19(cfg_cy_q19),
        .cfg_inv_fx_q30(cfg_inv_fx_q30),
        .cfg_inv_fy_q30(cfg_inv_fy_q30),
        .cfg_k1_q28(cfg_k1_q28),
        .cfg_k2_q28(cfg_k2_q28),
        .cfg_p1_q28(cfg_p1_q28),
        .cfg_p2_q28(cfg_p2_q28),
        .req_valid(mem_req_valid),
        .req_ready(mem_req_ready),
        .req_addr(mem_req_addr),
        .rsp_valid(mem_rsp_valid),
        .rsp_ready(mem_rsp_ready),
        .rsp_data(mem_rsp_data),
        .out_pixel(out_pixel),
        .out_valid(out_valid),
        .out_sof(out_sof),
        .out_eol(out_eol)
    );

    always @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            frame_busy <= 1'b0;
            scan_x <= {COORD_WIDTH{1'b0}};
            scan_y <= {COORD_WIDTH{1'b0}};
            output_y <= {COORD_WIDTH{1'b0}};
            all_pixels_issued <= 1'b0;
        end else begin
            if (!frame_busy) begin
                if (frame_start) begin
                    frame_busy <= 1'b1;
                    scan_x <= {COORD_WIDTH{1'b0}};
                    scan_y <= {COORD_WIDTH{1'b0}};
                    output_y <= {COORD_WIDTH{1'b0}};
                    all_pixels_issued <= 1'b0;
                end
            end else begin
                if (pipeline_input_accept) begin
                    if (scan_x == LAST_X) begin
                        scan_x <= {COORD_WIDTH{1'b0}};
                        if (scan_y == LAST_Y)
                            all_pixels_issued <= 1'b1;
                        else
                            scan_y <= scan_y + 1'b1;
                    end else begin
                        scan_x <= scan_x + 1'b1;
                    end
                end

                if (out_valid && out_eol) begin
                    if (output_y == LAST_Y) begin
                        frame_busy <= 1'b0;
                        all_pixels_issued <= 1'b0;
                    end else begin
                        output_y <= output_y + 1'b1;
                    end
                end
            end
        end
    end
endmodule

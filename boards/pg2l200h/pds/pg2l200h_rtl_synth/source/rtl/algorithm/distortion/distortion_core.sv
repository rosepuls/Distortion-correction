// Brown-Conrady coordinate mapper.
//
// Fixed-point formats:
//   camera centre/focal length : Q13.19
//   inverse focal length       : Q2.30
//   normalized coordinates     : Q4.28
//   distortion coefficients    : Q4.28
//   source coordinates         : Q13.19
//
// The datapath has five registered stages.  Configuration is sampled only
// with a valid SOF transfer, so all pixels in one frame use one camera model.
module distortion_core #(
    parameter integer IMAGE_WIDTH  = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer COORD_WIDTH  = 13
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire [COORD_WIDTH-1:0]       in_u,
    input  wire [COORD_WIDTH-1:0]       in_v,
    input  wire                         in_valid,
    input  wire                         in_sof,
    input  wire                         in_eol,
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
    output reg  signed [63:0]           out_src_x_q19,
    output reg  signed [63:0]           out_src_y_q19,
    output reg  signed [31:0]           out_x0,
    output reg  signed [31:0]           out_y0,
    output reg  [15:0]                  out_dx_q16,
    output reg  [15:0]                  out_dy_q16,
    output reg                          out_coord_valid,
    output reg                          out_valid,
    output reg                          out_sof,
    output reg                          out_eol
);

    // Frame-constant configuration registers.
    reg signed [31:0] frame_fx_q19, frame_fy_q19, frame_cx_q19, frame_cy_q19;
    reg signed [31:0] frame_inv_fx_q30, frame_inv_fy_q30;
    reg signed [31:0] frame_k1_q28, frame_k2_q28, frame_p1_q28, frame_p2_q28;

    // Stage 1: configuration selection and normalization.
    reg                         s1_valid, s1_sof, s1_eol;
    reg signed [31:0]           s1_x_q28, s1_y_q28;
    reg signed [31:0]           s1_fx_q19, s1_fy_q19, s1_cx_q19, s1_cy_q19;
    reg signed [31:0]           s1_k1_q28, s1_k2_q28, s1_p1_q28, s1_p2_q28;

    // Stage 2: r^2 operands.
    reg                         s2_valid, s2_sof, s2_eol;
    reg signed [31:0]           s2_x_q28, s2_y_q28;
    reg signed [63:0]           s2_x2_q56, s2_y2_q56, s2_xy_q56;
    reg signed [64:0]           s2_r2_q56;
    reg signed [31:0]           s2_fx_q19, s2_fy_q19, s2_cx_q19, s2_cy_q19;
    reg signed [31:0]           s2_k1_q28, s2_k2_q28, s2_p1_q28, s2_p2_q28;

    // Stage 3: r^4.
    reg                         s3_valid, s3_sof, s3_eol;
    reg signed [31:0]           s3_x_q28, s3_y_q28;
    reg signed [63:0]           s3_x2_q56, s3_y2_q56, s3_xy_q56;
    reg signed [64:0]           s3_r2_q56;
    reg signed [129:0]          s3_r4_q112;
    reg signed [31:0]           s3_fx_q19, s3_fy_q19, s3_cx_q19, s3_cy_q19;
    reg signed [31:0]           s3_k1_q28, s3_k2_q28, s3_p1_q28, s3_p2_q28;

    // Stage 4: radial and tangential distortion.
    reg                         s4_valid, s4_sof, s4_eol;
    reg signed [195:0]          s4_dist_x_q28, s4_dist_y_q28;
    reg signed [31:0]           s4_fx_q19, s4_fy_q19, s4_cx_q19, s4_cy_q19;

    wire signed [31:0] active_fx_q19 = (in_valid && in_sof) ? cfg_fx_q19 : frame_fx_q19;
    wire signed [31:0] active_fy_q19 = (in_valid && in_sof) ? cfg_fy_q19 : frame_fy_q19;
    wire signed [31:0] active_cx_q19 = (in_valid && in_sof) ? cfg_cx_q19 : frame_cx_q19;
    wire signed [31:0] active_cy_q19 = (in_valid && in_sof) ? cfg_cy_q19 : frame_cy_q19;
    wire signed [31:0] active_inv_fx_q30 = (in_valid && in_sof) ? cfg_inv_fx_q30 : frame_inv_fx_q30;
    wire signed [31:0] active_inv_fy_q30 = (in_valid && in_sof) ? cfg_inv_fy_q30 : frame_inv_fy_q30;
    wire signed [31:0] active_k1_q28 = (in_valid && in_sof) ? cfg_k1_q28 : frame_k1_q28;
    wire signed [31:0] active_k2_q28 = (in_valid && in_sof) ? cfg_k2_q28 : frame_k2_q28;
    wire signed [31:0] active_p1_q28 = (in_valid && in_sof) ? cfg_p1_q28 : frame_p1_q28;
    wire signed [31:0] active_p2_q28 = (in_valid && in_sof) ? cfg_p2_q28 : frame_p2_q28;

    wire signed [63:0] input_u_q19 = $signed({1'b0, in_u}) <<< 19;
    wire signed [63:0] input_v_q19 = $signed({1'b0, in_v}) <<< 19;
    wire signed [31:0] centered_x_q19 = input_u_q19 - active_cx_q19;
    wire signed [31:0] centered_y_q19 = input_v_q19 - active_cy_q19;
    wire signed [31:0] normalized_x_q28;
    wire signed [31:0] normalized_y_q28;

    normalize normalize_inst (
        .centered_x_q19(centered_x_q19),
        .centered_y_q19(centered_y_q19),
        .inv_fx_q30(active_inv_fx_q30),
        .inv_fy_q30(active_inv_fy_q30),
        .x_q28(normalized_x_q28),
        .y_q28(normalized_y_q28)
    );

    wire signed [63:0] s1_x2_q56_w = s1_x_q28 * s1_x_q28;
    wire signed [63:0] s1_y2_q56_w = s1_y_q28 * s1_y_q28;
    wire signed [63:0] s1_xy_q56_w = s1_x_q28 * s1_y_q28;
    wire signed [64:0] s1_r2_q56_w = $signed(s1_x2_q56_w) + $signed(s1_y2_q56_w);
    wire signed [129:0] s2_r4_q112_w = s2_r2_q56 * s2_r2_q56;

    wire signed [96:0]  k1_r2_product = s3_k1_q28 * s3_r2_q56;
    wire signed [161:0] k2_r4_product = s3_k2_q28 * s3_r4_q112;
    wire signed [162:0] radial_q56 = 163'sd72057594037927936 +
                                     ($signed(k1_r2_product) >>> 28) +
                                     ($signed(k2_r4_product) >>> 84);
    wire signed [194:0] radial_x_product = s3_x_q28 * radial_q56;
    wire signed [194:0] radial_y_product = s3_y_q28 * radial_q56;
    wire signed [96:0]  two_p1_xy_product = (s3_p1_q28 * s3_xy_q56) <<< 1;
    wire signed [96:0]  two_p2_xy_product = (s3_p2_q28 * s3_xy_q56) <<< 1;
    wire signed [65:0]  x_tangent_base = $signed(s3_r2_q56) + ($signed(s3_x2_q56) <<< 1);
    wire signed [65:0]  y_tangent_base = $signed(s3_r2_q56) + ($signed(s3_y2_q56) <<< 1);
    wire signed [97:0]  p2_x_tangent_product = s3_p2_q28 * x_tangent_base;
    wire signed [97:0]  p1_y_tangent_product = s3_p1_q28 * y_tangent_base;
    wire signed [98:0]  tangent_x_q56 = ($signed(two_p1_xy_product) >>> 28) +
                                         ($signed(p2_x_tangent_product) >>> 28);
    wire signed [98:0]  tangent_y_q56 = ($signed(p1_y_tangent_product) >>> 28) +
                                         ($signed(two_p2_xy_product) >>> 28);
    wire signed [195:0] distorted_x_q28 = ($signed(radial_x_product) >>> 56) +
                                           ($signed(tangent_x_q56) >>> 28);
    wire signed [195:0] distorted_y_q28 = ($signed(radial_y_product) >>> 56) +
                                           ($signed(tangent_y_q56) >>> 28);

    wire signed [227:0] source_x_product = s4_fx_q19 * s4_dist_x_q28;
    wire signed [227:0] source_y_product = s4_fy_q19 * s4_dist_y_q28;
    wire signed [228:0] source_x_full_q19 = ($signed(source_x_product) >>> 28) + $signed(s4_cx_q19);
    wire signed [228:0] source_y_full_q19 = ($signed(source_y_product) >>> 28) + $signed(s4_cy_q19);
    wire signed [63:0] source_x_q19 = source_x_full_q19[63:0];
    wire signed [63:0] source_y_q19 = source_y_full_q19[63:0];
    wire signed [31:0] split_x0, split_y0;
    wire [15:0] split_dx_q16, split_dy_q16;
    wire split_coord_valid;

    coordinate_split #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) coordinate_split_inst (
        .src_x_q19(source_x_q19), .src_y_q19(source_y_q19),
        .x0(split_x0), .y0(split_y0),
        .dx_q16(split_dx_q16), .dy_q16(split_dy_q16),
        .coord_valid(split_coord_valid)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_fx_q19 <= 32'sd0; frame_fy_q19 <= 32'sd0;
            frame_cx_q19 <= 32'sd0; frame_cy_q19 <= 32'sd0;
            frame_inv_fx_q30 <= 32'sd0; frame_inv_fy_q30 <= 32'sd0;
            frame_k1_q28 <= 32'sd0; frame_k2_q28 <= 32'sd0;
            frame_p1_q28 <= 32'sd0; frame_p2_q28 <= 32'sd0;
            s1_valid <= 1'b0; s2_valid <= 1'b0; s3_valid <= 1'b0; s4_valid <= 1'b0;
            out_valid <= 1'b0; out_sof <= 1'b0; out_eol <= 1'b0;
            out_src_x_q19 <= 64'sd0; out_src_y_q19 <= 64'sd0;
            out_x0 <= 32'sd0; out_y0 <= 32'sd0;
            out_dx_q16 <= 16'sd0; out_dy_q16 <= 16'sd0; out_coord_valid <= 1'b0;
        end else begin
            // Stage 5: denormalize and split the source coordinate.
            out_valid <= s4_valid;
            out_sof <= s4_valid && s4_sof;
            out_eol <= s4_valid && s4_eol;
            if (s4_valid) begin
                out_src_x_q19 <= source_x_q19;
                out_src_y_q19 <= source_y_q19;
                out_x0 <= split_x0; out_y0 <= split_y0;
                out_dx_q16 <= split_dx_q16; out_dy_q16 <= split_dy_q16;
                out_coord_valid <= split_coord_valid;
            end else begin
                out_src_x_q19 <= 64'sd0; out_src_y_q19 <= 64'sd0;
                out_x0 <= 32'sd0; out_y0 <= 32'sd0;
                out_dx_q16 <= 16'sd0; out_dy_q16 <= 16'sd0; out_coord_valid <= 1'b0;
            end

            // Stage 4: apply radial and tangential polynomial terms.
            s4_valid <= s3_valid;
            s4_sof <= s3_sof;
            s4_eol <= s3_eol;
            s4_dist_x_q28 <= distorted_x_q28;
            s4_dist_y_q28 <= distorted_y_q28;
            s4_fx_q19 <= s3_fx_q19; s4_fy_q19 <= s3_fy_q19;
            s4_cx_q19 <= s3_cx_q19; s4_cy_q19 <= s3_cy_q19;

            // Stage 3: calculate r^4.
            s3_valid <= s2_valid;
            s3_sof <= s2_sof;
            s3_eol <= s2_eol;
            s3_x_q28 <= s2_x_q28; s3_y_q28 <= s2_y_q28;
            s3_x2_q56 <= s2_x2_q56; s3_y2_q56 <= s2_y2_q56; s3_xy_q56 <= s2_xy_q56;
            s3_r2_q56 <= s2_r2_q56;
            s3_r4_q112 <= s2_r4_q112_w;
            s3_fx_q19 <= s2_fx_q19; s3_fy_q19 <= s2_fy_q19;
            s3_cx_q19 <= s2_cx_q19; s3_cy_q19 <= s2_cy_q19;
            s3_k1_q28 <= s2_k1_q28; s3_k2_q28 <= s2_k2_q28;
            s3_p1_q28 <= s2_p1_q28; s3_p2_q28 <= s2_p2_q28;

            // Stage 2: calculate r^2 and xy.
            s2_valid <= s1_valid;
            s2_sof <= s1_sof;
            s2_eol <= s1_eol;
            s2_x_q28 <= s1_x_q28; s2_y_q28 <= s1_y_q28;
            s2_x2_q56 <= s1_x2_q56_w; s2_y2_q56 <= s1_y2_q56_w; s2_xy_q56 <= s1_xy_q56_w;
            s2_r2_q56 <= s1_r2_q56_w;
            s2_fx_q19 <= s1_fx_q19; s2_fy_q19 <= s1_fy_q19;
            s2_cx_q19 <= s1_cx_q19; s2_cy_q19 <= s1_cy_q19;
            s2_k1_q28 <= s1_k1_q28; s2_k2_q28 <= s1_k2_q28;
            s2_p1_q28 <= s1_p1_q28; s2_p2_q28 <= s1_p2_q28;

            // Stage 1: latch a frame configuration at SOF and normalize input.
            s1_valid <= in_valid;
            s1_sof <= in_valid && in_sof;
            s1_eol <= in_valid && in_eol;
            s1_x_q28 <= normalized_x_q28; s1_y_q28 <= normalized_y_q28;
            s1_fx_q19 <= active_fx_q19; s1_fy_q19 <= active_fy_q19;
            s1_cx_q19 <= active_cx_q19; s1_cy_q19 <= active_cy_q19;
            s1_k1_q28 <= active_k1_q28; s1_k2_q28 <= active_k2_q28;
            s1_p1_q28 <= active_p1_q28; s1_p2_q28 <= active_p2_q28;
            if (in_valid && in_sof) begin
                frame_fx_q19 <= cfg_fx_q19; frame_fy_q19 <= cfg_fy_q19;
                frame_cx_q19 <= cfg_cx_q19; frame_cy_q19 <= cfg_cy_q19;
                frame_inv_fx_q30 <= cfg_inv_fx_q30; frame_inv_fy_q30 <= cfg_inv_fy_q30;
                frame_k1_q28 <= cfg_k1_q28; frame_k2_q28 <= cfg_k2_q28;
                frame_p1_q28 <= cfg_p1_q28; frame_p2_q28 <= cfg_p2_q28;
            end
        end
    end
endmodule

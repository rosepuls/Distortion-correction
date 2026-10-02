`timescale 1ns/1ps

// 1-pixel/clock narrowed Brown-Conrady mapper.
// Selected internal format: centered S23.Q12, inverse S26.Q24,
// normalized/coefficient/r2 S20.Q18, radial/distorted S21.Q18,
// focal S24.Q12. Every narrowing point explicitly saturates so this RTL
// remains bit-exact with source_coordinates_horner_quantized.
module distortion_core_optimized #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer IMAGE_HEIGHT = 720,
    parameter integer COORD_WIDTH = 13
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
    output reg signed [63:0]            out_src_x_q19,
    output reg signed [63:0]            out_src_y_q19,
    output reg signed [31:0]            out_x0,
    output reg signed [31:0]            out_y0,
    output reg [15:0]                   out_dx_q16,
    output reg [15:0]                   out_dy_q16,
    output reg                          out_coord_valid,
    output reg                          out_valid,
    output reg                          out_sof,
    output reg                          out_eol
);
    function automatic signed [19:0] saturate_s20;
        input signed [63:0] value;
        begin
            if (value > 64'sd524287)
                saturate_s20 = 20'sh7ffff;
            else if (value < -64'sd524288)
                saturate_s20 = -20'sd524288;
            else
                saturate_s20 = value[19:0];
        end
    endfunction

    function automatic signed [20:0] saturate_s21;
        input signed [63:0] value;
        begin
            if (value > 64'sd1048575)
                saturate_s21 = 21'sh0fffff;
            else if (value < -64'sd1048576)
                saturate_s21 = -21'sd1048576;
            else
                saturate_s21 = value[20:0];
        end
    endfunction

    function automatic signed [22:0] saturate_s23;
        input signed [63:0] value;
        begin
            if (value > 64'sd4194303)
                saturate_s23 = 23'sh3fffff;
            else if (value < -64'sd4194304)
                saturate_s23 = -23'sd4194304;
            else
                saturate_s23 = value[22:0];
        end
    endfunction

    function automatic signed [23:0] saturate_s24;
        input signed [63:0] value;
        begin
            if (value > 64'sd8388607)
                saturate_s24 = 24'sh7fffff;
            else if (value < -64'sd8388608)
                saturate_s24 = -24'sd8388608;
            else
                saturate_s24 = value[23:0];
        end
    endfunction

    function automatic signed [25:0] saturate_s26;
        input signed [63:0] value;
        begin
            if (value > 64'sd33554431)
                saturate_s26 = 26'sh1ffffff;
            else if (value < -64'sd33554432)
                saturate_s26 = -26'sd33554432;
            else
                saturate_s26 = value[25:0];
        end
    endfunction

    reg signed [31:0] frame_fx_q19;
    reg signed [31:0] frame_fy_q19;
    reg signed [31:0] frame_cx_q19;
    reg signed [31:0] frame_cy_q19;
    reg signed [31:0] frame_inv_fx_q30;
    reg signed [31:0] frame_inv_fy_q30;
    reg signed [31:0] frame_k1_q28;
    reg signed [31:0] frame_k2_q28;
    reg signed [31:0] frame_p1_q28;
    reg signed [31:0] frame_p2_q28;

    // Stage 0 captures one input coordinate and its frame-stable calibration.
    // In particular, in_sof only selects register inputs here; it no longer
    // drives the center/subtract/multiply chain in stage 1.
    reg stage0_valid;
    reg stage0_sof;
    reg stage0_eol;
    reg [COORD_WIDTH-1:0] stage0_u;
    reg [COORD_WIDTH-1:0] stage0_v;
    // PDS otherwise proves these frame-stable registers equivalent to the
    // frame registers and merges them away, which would undo this pipeline.
    reg signed [31:0] stage0_fx_q19     /* synthesis syn_preserve = 1 */;
    reg signed [31:0] stage0_fy_q19     /* synthesis syn_preserve = 1 */;
    reg signed [31:0] stage0_cx_q19     /* synthesis syn_preserve = 1 */;
    reg signed [31:0] stage0_cy_q19     /* synthesis syn_preserve = 1 */;
    reg signed [31:0] stage0_inv_fx_q30 /* synthesis syn_preserve = 1 */;
    reg signed [31:0] stage0_inv_fy_q30 /* synthesis syn_preserve = 1 */;
    reg signed [31:0] stage0_k1_q28     /* synthesis syn_preserve = 1 */;
    reg signed [31:0] stage0_k2_q28     /* synthesis syn_preserve = 1 */;
    reg signed [31:0] stage0_p1_q28     /* synthesis syn_preserve = 1 */;
    reg signed [31:0] stage0_p2_q28     /* synthesis syn_preserve = 1 */;

    // Stage 1C separates center subtraction/quantization from the
    // normalized-coordinate multipliers in Stage 1.
    reg stage1c_valid;
    reg stage1c_sof;
    reg stage1c_eol;
    reg signed [22:0] stage1c_centered_x_q12;
    reg signed [22:0] stage1c_centered_y_q12;
    reg signed [25:0] stage1c_inverse_fx_q24;
    reg signed [25:0] stage1c_inverse_fy_q24;
    reg signed [31:0] stage1c_k1_q28;
    reg signed [31:0] stage1c_k2_q28;
    reg signed [31:0] stage1c_p1_q28;
    reg signed [31:0] stage1c_p2_q28;
    reg signed [31:0] stage1c_fx_q19;
    reg signed [31:0] stage1c_fy_q19;
    reg signed [31:0] stage1c_cx_q19;
    reg signed [31:0] stage1c_cy_q19;

    // Stage 1M and Stage 1S explicitly pipeline the two 23x26 normalized
    // coordinate multiplications.  Splitting at bit 18 is exact:
    //   A*B = p00 + (p10+p01)*2^18 + p11*2^36.
    // This replaces each long four-APM combinational chain with an 18x18
    // low-product stage followed by a short registered reconstruction stage.
    reg stage1m_valid;
    reg stage1m_sof;
    reg stage1m_eol;
    reg [35:0] stage1m_x_p00 /* synthesis syn_preserve = 1 */;
    reg signed [22:0] stage1m_x_p10 /* synthesis syn_preserve = 1 */;
    reg signed [25:0] stage1m_x_p01 /* synthesis syn_preserve = 1 */;
    reg signed [12:0] stage1m_x_p11 /* synthesis syn_preserve = 1 */;
    reg [35:0] stage1m_y_p00 /* synthesis syn_preserve = 1 */;
    reg signed [22:0] stage1m_y_p10 /* synthesis syn_preserve = 1 */;
    reg signed [25:0] stage1m_y_p01 /* synthesis syn_preserve = 1 */;
    reg signed [12:0] stage1m_y_p11 /* synthesis syn_preserve = 1 */;
    reg signed [31:0] stage1m_k1_q28;
    reg signed [31:0] stage1m_k2_q28;
    reg signed [31:0] stage1m_p1_q28;
    reg signed [31:0] stage1m_p2_q28;
    reg signed [31:0] stage1m_fx_q19;
    reg signed [31:0] stage1m_fy_q19;
    reg signed [31:0] stage1m_cx_q19;
    reg signed [31:0] stage1m_cy_q19;

    reg stage1s_valid;
    reg stage1s_sof;
    reg stage1s_eol;
    reg [35:0] stage1s_x_p00 /* synthesis syn_preserve = 1 */;
    reg signed [26:0] stage1s_x_cross_sum /* synthesis syn_preserve = 1 */;
    reg signed [12:0] stage1s_x_p11 /* synthesis syn_preserve = 1 */;
    reg [35:0] stage1s_y_p00 /* synthesis syn_preserve = 1 */;
    reg signed [26:0] stage1s_y_cross_sum /* synthesis syn_preserve = 1 */;
    reg signed [12:0] stage1s_y_p11 /* synthesis syn_preserve = 1 */;
    reg signed [31:0] stage1s_k1_q28;
    reg signed [31:0] stage1s_k2_q28;
    reg signed [31:0] stage1s_p1_q28;
    reg signed [31:0] stage1s_p2_q28;
    reg signed [31:0] stage1s_fx_q19;
    reg signed [31:0] stage1s_fy_q19;
    reg signed [31:0] stage1s_cx_q19;
    reg signed [31:0] stage1s_cy_q19;

    reg stage1_valid;
    reg stage1_sof;
    reg stage1_eol;
    reg signed [19:0] stage1_x_q18;
    reg signed [19:0] stage1_y_q18;
    reg signed [19:0] stage1_k1_q18;
    reg signed [19:0] stage1_k2_q18;
    reg signed [19:0] stage1_p1_q18;
    reg signed [19:0] stage1_p2_q18;
    reg signed [23:0] stage1_fx_q12;
    reg signed [23:0] stage1_fy_q12;
    reg signed [23:0] stage1_cx_q12;
    reg signed [23:0] stage1_cy_q12;

    // These two radial-polynomial pipeline boundaries must remain physical
    // registers.  PDS otherwise retimes them through the multiplier inputs
    // and recreates an x2/r2/Horner combinational chain at 100 MHz.
    reg stage2_valid /* synthesis syn_preserve = 1 */;
    reg stage2_sof /* synthesis syn_preserve = 1 */;
    reg stage2_eol /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2_x_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2_y_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2_x2_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2_y2_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2_xy_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2_r2_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2_k1_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2_k2_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2_p1_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2_p2_q18 /* synthesis syn_preserve = 1 */;
    reg signed [23:0] stage2_fx_q12 /* synthesis syn_preserve = 1 */;
    reg signed [23:0] stage2_fy_q12 /* synthesis syn_preserve = 1 */;
    reg signed [23:0] stage2_cx_q12 /* synthesis syn_preserve = 1 */;
    reg signed [23:0] stage2_cy_q12 /* synthesis syn_preserve = 1 */;

    // Stage 2H holds the Horner result before the second radial multiply.
    // This prevents k2*r2, Horner addition, and r2*Horner from becoming one
    // long combinational chain.
    reg stage2h_valid /* synthesis syn_preserve = 1 */;
    reg stage2h_sof /* synthesis syn_preserve = 1 */;
    reg stage2h_eol /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2h_x_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2h_y_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2h_x2_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2h_y2_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2h_xy_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2h_r2_q18 /* synthesis syn_preserve = 1 */;
    reg signed [20:0] stage2h_horner_t_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2h_p1_q18 /* synthesis syn_preserve = 1 */;
    reg signed [19:0] stage2h_p2_q18 /* synthesis syn_preserve = 1 */;
    reg signed [23:0] stage2h_fx_q12 /* synthesis syn_preserve = 1 */;
    reg signed [23:0] stage2h_fy_q12 /* synthesis syn_preserve = 1 */;
    reg signed [23:0] stage2h_cx_q12 /* synthesis syn_preserve = 1 */;
    reg signed [23:0] stage2h_cy_q12 /* synthesis syn_preserve = 1 */;

    reg stage3_valid;
    reg stage3_sof;
    reg stage3_eol;
    reg signed [19:0] stage3_x_q18;
    reg signed [19:0] stage3_y_q18;
    reg signed [19:0] stage3_x2_q18;
    reg signed [19:0] stage3_y2_q18;
    reg signed [19:0] stage3_xy_q18;
    reg signed [19:0] stage3_r2_q18;
    reg signed [20:0] stage3_radial_q18;
    reg signed [19:0] stage3_p1_q18;
    reg signed [19:0] stage3_p2_q18;
    reg signed [23:0] stage3_fx_q12;
    reg signed [23:0] stage3_fy_q12;
    reg signed [23:0] stage3_cx_q12;
    reg signed [23:0] stage3_cy_q12;

    // Stage 4 registers the first radial/tangential products.  Tangential
    // bases need 22 signed bits at most: 524287 + 2*524287 = 1572861.
    reg stage4_valid;
    reg stage4_sof;
    reg stage4_eol;
    reg signed [40:0] stage4_radial_x_product;
    reg signed [40:0] stage4_radial_y_product;
    reg signed [39:0] stage4_p1_xy_product;
    reg signed [39:0] stage4_p2_xy_product;
    reg signed [21:0] stage4_tangential_x_base;
    reg signed [21:0] stage4_tangential_y_base;
    reg signed [19:0] stage4_p1_q18;
    reg signed [19:0] stage4_p2_q18;
    reg signed [23:0] stage4_fx_q12;
    reg signed [23:0] stage4_fy_q12;
    reg signed [23:0] stage4_cx_q12;
    reg signed [23:0] stage4_cy_q12;

    // Stage 5 isolates coefficient multipliers from tangential summation.
    reg stage5_valid;
    reg stage5_sof;
    reg stage5_eol;
    reg signed [20:0] stage5_radial_x_q18;
    reg signed [20:0] stage5_radial_y_q18;
    reg signed [20:0] stage5_tangential_x_term1;
    reg signed [20:0] stage5_tangential_x_term2;
    reg signed [20:0] stage5_tangential_y_term1;
    reg signed [20:0] stage5_tangential_y_term2;
    reg signed [23:0] stage5_fx_q12;
    reg signed [23:0] stage5_fy_q12;
    reg signed [23:0] stage5_cx_q12;
    reg signed [23:0] stage5_cy_q12;

    reg stage6_valid;
    reg stage6_sof;
    reg stage6_eol;
    reg signed [20:0] stage6_radial_x_q18;
    reg signed [20:0] stage6_radial_y_q18;
    reg signed [20:0] stage6_tangential_x_q18;
    reg signed [20:0] stage6_tangential_y_q18;
    reg signed [23:0] stage6_fx_q12;
    reg signed [23:0] stage6_fy_q12;
    reg signed [23:0] stage6_cx_q12;
    reg signed [23:0] stage6_cy_q12;

    reg stage7_valid;
    reg stage7_sof;
    reg stage7_eol;
    reg signed [20:0] stage7_xd_q18;
    reg signed [20:0] stage7_yd_q18;
    reg signed [23:0] stage7_fx_q12;
    reg signed [23:0] stage7_fy_q12;
    reg signed [23:0] stage7_cx_q12;
    reg signed [23:0] stage7_cy_q12;

    reg stage8_valid;
    reg stage8_sof;
    reg stage8_eol;
    reg signed [44:0] stage8_source_x_product;
    reg signed [44:0] stage8_source_y_product;
    reg signed [23:0] stage8_cx_q12;
    reg signed [23:0] stage8_cy_q12;

    reg stage9_valid;
    reg stage9_sof;
    reg stage9_eol;
    reg signed [63:0] stage9_source_x_q19;
    reg signed [63:0] stage9_source_y_q19;

    wire signed [63:0] unsigned_u_extended =
        {{(64-COORD_WIDTH){1'b0}}, stage0_u};
    wire signed [63:0] unsigned_v_extended =
        {{(64-COORD_WIDTH){1'b0}}, stage0_v};
    wire signed [63:0] centered_x_q19 =
        (unsigned_u_extended <<< 19) - stage0_cx_q19;
    wire signed [63:0] centered_y_q19 =
        (unsigned_v_extended <<< 19) - stage0_cy_q19;
    wire signed [22:0] centered_x_q12 = saturate_s23(centered_x_q19 >>> 7);
    wire signed [22:0] centered_y_q12 = saturate_s23(centered_y_q19 >>> 7);
    wire signed [25:0] inverse_fx_q24 = saturate_s26(stage0_inv_fx_q30 >>> 6);
    wire signed [25:0] inverse_fy_q24 = saturate_s26(stage0_inv_fy_q30 >>> 6);
    wire signed [26:0] stage1m_x_cross_sum =
        $signed({{4{stage1m_x_p10[22]}}, stage1m_x_p10}) +
        $signed({{1{stage1m_x_p01[25]}}, stage1m_x_p01});
    wire signed [26:0] stage1m_y_cross_sum =
        $signed({{4{stage1m_y_p10[22]}}, stage1m_y_p10}) +
        $signed({{1{stage1m_y_p01[25]}}, stage1m_y_p01});
    wire signed [63:0] normalized_x_product =
        $signed({28'd0, stage1s_x_p00}) +
        ($signed({{37{stage1s_x_cross_sum[26]}},
                  stage1s_x_cross_sum}) <<< 18) +
        ($signed({{51{stage1s_x_p11[12]}}, stage1s_x_p11}) <<< 36);
    wire signed [63:0] normalized_y_product =
        $signed({28'd0, stage1s_y_p00}) +
        ($signed({{37{stage1s_y_cross_sum[26]}},
                  stage1s_y_cross_sum}) <<< 18) +
        ($signed({{51{stage1s_y_p11[12]}}, stage1s_y_p11}) <<< 36);

    wire signed [39:0] x_squared_product = stage1_x_q18 * stage1_x_q18;
    wire signed [39:0] y_squared_product = stage1_y_q18 * stage1_y_q18;
    wire signed [39:0] xy_product = stage1_x_q18 * stage1_y_q18;
    wire signed [19:0] x_squared_q18 =
        saturate_s20($signed(x_squared_product) >>> 18);
    wire signed [19:0] y_squared_q18 =
        saturate_s20($signed(y_squared_product) >>> 18);
    wire signed [19:0] xy_q18 = saturate_s20($signed(xy_product) >>> 18);
    wire signed [63:0] radius_sum_q18 =
        {{44{x_squared_q18[19]}}, x_squared_q18} +
        {{44{y_squared_q18[19]}}, y_squared_q18};
    wire signed [19:0] radius_squared_q18 = saturate_s20(radius_sum_q18);

    wire signed [39:0] k2_radius_product = stage2_k2_q18 * stage2_r2_q18;
    wire signed [20:0] k2_radius_q18 =
        saturate_s21($signed(k2_radius_product) >>> 18);
    wire signed [63:0] horner_sum_q18 =
        {{44{stage2_k1_q18[19]}}, stage2_k1_q18} +
        {{43{k2_radius_q18[20]}}, k2_radius_q18};
    wire signed [20:0] horner_t_q18 = saturate_s21(horner_sum_q18);
    wire signed [40:0] radial_product = stage2h_r2_q18 * stage2h_horner_t_q18;
    wire signed [20:0] radial_delta_q18 =
        saturate_s21($signed(radial_product) >>> 18);
    wire signed [63:0] radial_sum_q18 =
        64'sd262144 + {{43{radial_delta_q18[20]}}, radial_delta_q18};
    wire signed [20:0] radial_q18 = saturate_s21(radial_sum_q18);

    wire signed [40:0] radial_x_product = stage3_x_q18 * stage3_radial_q18;
    wire signed [40:0] radial_y_product = stage3_y_q18 * stage3_radial_q18;
    wire signed [39:0] p1_xy_product = stage3_p1_q18 * stage3_xy_q18;
    wire signed [39:0] p2_xy_product = stage3_p2_q18 * stage3_xy_q18;
    wire signed [21:0] tangential_x_base =
        {{2{stage3_r2_q18[19]}}, stage3_r2_q18} +
        ({{2{stage3_x2_q18[19]}}, stage3_x2_q18} <<< 1);
    wire signed [21:0] tangential_y_base =
        {{2{stage3_r2_q18[19]}}, stage3_r2_q18} +
        ({{2{stage3_y2_q18[19]}}, stage3_y2_q18} <<< 1);

    wire signed [41:0] p2_base_product =
        stage4_p2_q18 * stage4_tangential_x_base;
    wire signed [41:0] p1_base_product =
        stage4_p1_q18 * stage4_tangential_y_base;
    wire signed [20:0] radial_x_q18 =
        saturate_s21($signed(stage4_radial_x_product) >>> 18);
    wire signed [20:0] radial_y_q18 =
        saturate_s21($signed(stage4_radial_y_product) >>> 18);
    wire signed [20:0] tangential_x_term1 =
        saturate_s21($signed(stage4_p1_xy_product) >>> 17);
    wire signed [20:0] tangential_x_term2 =
        saturate_s21($signed(p2_base_product) >>> 18);
    wire signed [20:0] tangential_y_term1 =
        saturate_s21($signed(p1_base_product) >>> 18);
    wire signed [20:0] tangential_y_term2 =
        saturate_s21($signed(stage4_p2_xy_product) >>> 17);
    wire signed [63:0] tangential_x_sum =
        {{43{stage5_tangential_x_term1[20]}},
         stage5_tangential_x_term1} +
        {{43{stage5_tangential_x_term2[20]}},
         stage5_tangential_x_term2};
    wire signed [63:0] tangential_y_sum =
        {{43{stage5_tangential_y_term1[20]}},
         stage5_tangential_y_term1} +
        {{43{stage5_tangential_y_term2[20]}},
         stage5_tangential_y_term2};
    wire signed [20:0] tangential_x_q18 = saturate_s21(tangential_x_sum);
    wire signed [20:0] tangential_y_q18 = saturate_s21(tangential_y_sum);
    wire signed [63:0] distorted_x_sum =
        {{43{stage6_radial_x_q18[20]}}, stage6_radial_x_q18} +
        {{43{stage6_tangential_x_q18[20]}}, stage6_tangential_x_q18};
    wire signed [63:0] distorted_y_sum =
        {{43{stage6_radial_y_q18[20]}}, stage6_radial_y_q18} +
        {{43{stage6_tangential_y_q18[20]}}, stage6_tangential_y_q18};
    wire signed [20:0] distorted_x_q18 = saturate_s21(distorted_x_sum);
    wire signed [20:0] distorted_y_q18 = saturate_s21(distorted_y_sum);

    wire signed [44:0] source_x_product = stage7_fx_q12 * stage7_xd_q18;
    wire signed [44:0] source_y_product = stage7_fy_q12 * stage7_yd_q18;
    wire signed [63:0] source_x_product_extended =
        {{19{stage8_source_x_product[44]}}, stage8_source_x_product};
    wire signed [63:0] source_y_product_extended =
        {{19{stage8_source_y_product[44]}}, stage8_source_y_product};
    wire signed [63:0] source_cx_extended =
        {{40{stage8_cx_q12[23]}}, stage8_cx_q12};
    wire signed [63:0] source_cy_extended =
        {{40{stage8_cy_q12[23]}}, stage8_cy_q12};
    wire signed [63:0] source_x_q19 =
        (source_x_product_extended >>> 11) + (source_cx_extended <<< 7);
    wire signed [63:0] source_y_q19 =
        (source_y_product_extended >>> 11) + (source_cy_extended <<< 7);

    wire signed [31:0] split_x0;
    wire signed [31:0] split_y0;
    wire [15:0] split_dx_q16;
    wire [15:0] split_dy_q16;
    wire split_coord_valid;

    coordinate_split #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) coordinate_split_inst (
        .src_x_q19(stage9_source_x_q19),
        .src_y_q19(stage9_source_y_q19),
        .x0(split_x0),
        .y0(split_y0),
        .dx_q16(split_dx_q16),
        .dy_q16(split_dy_q16),
        .coord_valid(split_coord_valid)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_fx_q19 <= 32'sd0;
            frame_fy_q19 <= 32'sd0;
            frame_cx_q19 <= 32'sd0;
            frame_cy_q19 <= 32'sd0;
            frame_inv_fx_q30 <= 32'sd0;
            frame_inv_fy_q30 <= 32'sd0;
            frame_k1_q28 <= 32'sd0;
            frame_k2_q28 <= 32'sd0;
            frame_p1_q28 <= 32'sd0;
            frame_p2_q28 <= 32'sd0;
            stage0_valid <= 1'b0;
            stage0_sof <= 1'b0;
            stage0_eol <= 1'b0;
            stage0_u <= {COORD_WIDTH{1'b0}};
            stage0_v <= {COORD_WIDTH{1'b0}};
            stage0_fx_q19 <= 32'sd0;
            stage0_fy_q19 <= 32'sd0;
            stage0_cx_q19 <= 32'sd0;
            stage0_cy_q19 <= 32'sd0;
            stage0_inv_fx_q30 <= 32'sd0;
            stage0_inv_fy_q30 <= 32'sd0;
            stage0_k1_q28 <= 32'sd0;
            stage0_k2_q28 <= 32'sd0;
            stage0_p1_q28 <= 32'sd0;
            stage0_p2_q28 <= 32'sd0;
            stage1c_valid <= 1'b0;
            stage1c_sof <= 1'b0;
            stage1c_eol <= 1'b0;
            stage1c_centered_x_q12 <= 23'sd0;
            stage1c_centered_y_q12 <= 23'sd0;
            stage1c_inverse_fx_q24 <= 26'sd0;
            stage1c_inverse_fy_q24 <= 26'sd0;
            stage1c_k1_q28 <= 32'sd0;
            stage1c_k2_q28 <= 32'sd0;
            stage1c_p1_q28 <= 32'sd0;
            stage1c_p2_q28 <= 32'sd0;
            stage1c_fx_q19 <= 32'sd0;
            stage1c_fy_q19 <= 32'sd0;
            stage1c_cx_q19 <= 32'sd0;
            stage1c_cy_q19 <= 32'sd0;
            stage1m_valid <= 1'b0;
            stage1m_sof <= 1'b0;
            stage1m_eol <= 1'b0;
            stage1m_x_p00 <= 36'd0;
            stage1m_x_p10 <= 23'sd0;
            stage1m_x_p01 <= 26'sd0;
            stage1m_x_p11 <= 13'sd0;
            stage1m_y_p00 <= 36'd0;
            stage1m_y_p10 <= 23'sd0;
            stage1m_y_p01 <= 26'sd0;
            stage1m_y_p11 <= 13'sd0;
            stage1m_k1_q28 <= 32'sd0;
            stage1m_k2_q28 <= 32'sd0;
            stage1m_p1_q28 <= 32'sd0;
            stage1m_p2_q28 <= 32'sd0;
            stage1m_fx_q19 <= 32'sd0;
            stage1m_fy_q19 <= 32'sd0;
            stage1m_cx_q19 <= 32'sd0;
            stage1m_cy_q19 <= 32'sd0;
            stage1s_valid <= 1'b0;
            stage1s_sof <= 1'b0;
            stage1s_eol <= 1'b0;
            stage1s_x_p00 <= 36'd0;
            stage1s_x_cross_sum <= 27'sd0;
            stage1s_x_p11 <= 13'sd0;
            stage1s_y_p00 <= 36'd0;
            stage1s_y_cross_sum <= 27'sd0;
            stage1s_y_p11 <= 13'sd0;
            stage1s_k1_q28 <= 32'sd0;
            stage1s_k2_q28 <= 32'sd0;
            stage1s_p1_q28 <= 32'sd0;
            stage1s_p2_q28 <= 32'sd0;
            stage1s_fx_q19 <= 32'sd0;
            stage1s_fy_q19 <= 32'sd0;
            stage1s_cx_q19 <= 32'sd0;
            stage1s_cy_q19 <= 32'sd0;
            stage1_valid <= 1'b0;
            stage1_sof <= 1'b0;
            stage1_eol <= 1'b0;
            stage1_x_q18 <= 20'sd0;
            stage1_y_q18 <= 20'sd0;
            stage1_k1_q18 <= 20'sd0;
            stage1_k2_q18 <= 20'sd0;
            stage1_p1_q18 <= 20'sd0;
            stage1_p2_q18 <= 20'sd0;
            stage1_fx_q12 <= 24'sd0;
            stage1_fy_q12 <= 24'sd0;
            stage1_cx_q12 <= 24'sd0;
            stage1_cy_q12 <= 24'sd0;
            stage2_valid <= 1'b0;
            stage2_sof <= 1'b0;
            stage2_eol <= 1'b0;
            stage2_x_q18 <= 20'sd0;
            stage2_y_q18 <= 20'sd0;
            stage2_x2_q18 <= 20'sd0;
            stage2_y2_q18 <= 20'sd0;
            stage2_xy_q18 <= 20'sd0;
            stage2_r2_q18 <= 20'sd0;
            stage2_k1_q18 <= 20'sd0;
            stage2_k2_q18 <= 20'sd0;
            stage2_p1_q18 <= 20'sd0;
            stage2_p2_q18 <= 20'sd0;
            stage2_fx_q12 <= 24'sd0;
            stage2_fy_q12 <= 24'sd0;
            stage2_cx_q12 <= 24'sd0;
            stage2_cy_q12 <= 24'sd0;
            stage2h_valid <= 1'b0;
            stage2h_sof <= 1'b0;
            stage2h_eol <= 1'b0;
            stage2h_x_q18 <= 20'sd0;
            stage2h_y_q18 <= 20'sd0;
            stage2h_x2_q18 <= 20'sd0;
            stage2h_y2_q18 <= 20'sd0;
            stage2h_xy_q18 <= 20'sd0;
            stage2h_r2_q18 <= 20'sd0;
            stage2h_horner_t_q18 <= 21'sd0;
            stage2h_p1_q18 <= 20'sd0;
            stage2h_p2_q18 <= 20'sd0;
            stage2h_fx_q12 <= 24'sd0;
            stage2h_fy_q12 <= 24'sd0;
            stage2h_cx_q12 <= 24'sd0;
            stage2h_cy_q12 <= 24'sd0;
            stage3_valid <= 1'b0;
            stage3_sof <= 1'b0;
            stage3_eol <= 1'b0;
            stage3_x_q18 <= 20'sd0;
            stage3_y_q18 <= 20'sd0;
            stage3_x2_q18 <= 20'sd0;
            stage3_y2_q18 <= 20'sd0;
            stage3_xy_q18 <= 20'sd0;
            stage3_r2_q18 <= 20'sd0;
            stage3_radial_q18 <= 21'sd0;
            stage3_p1_q18 <= 20'sd0;
            stage3_p2_q18 <= 20'sd0;
            stage3_fx_q12 <= 24'sd0;
            stage3_fy_q12 <= 24'sd0;
            stage3_cx_q12 <= 24'sd0;
            stage3_cy_q12 <= 24'sd0;
            stage4_valid <= 1'b0;
            stage4_sof <= 1'b0;
            stage4_eol <= 1'b0;
            stage4_radial_x_product <= 41'sd0;
            stage4_radial_y_product <= 41'sd0;
            stage4_p1_xy_product <= 40'sd0;
            stage4_p2_xy_product <= 40'sd0;
            stage4_tangential_x_base <= 22'sd0;
            stage4_tangential_y_base <= 22'sd0;
            stage4_p1_q18 <= 20'sd0;
            stage4_p2_q18 <= 20'sd0;
            stage4_fx_q12 <= 24'sd0;
            stage4_fy_q12 <= 24'sd0;
            stage4_cx_q12 <= 24'sd0;
            stage4_cy_q12 <= 24'sd0;
            stage5_valid <= 1'b0;
            stage5_sof <= 1'b0;
            stage5_eol <= 1'b0;
            stage5_radial_x_q18 <= 21'sd0;
            stage5_radial_y_q18 <= 21'sd0;
            stage5_tangential_x_term1 <= 21'sd0;
            stage5_tangential_x_term2 <= 21'sd0;
            stage5_tangential_y_term1 <= 21'sd0;
            stage5_tangential_y_term2 <= 21'sd0;
            stage5_fx_q12 <= 24'sd0;
            stage5_fy_q12 <= 24'sd0;
            stage5_cx_q12 <= 24'sd0;
            stage5_cy_q12 <= 24'sd0;
            stage6_valid <= 1'b0;
            stage6_sof <= 1'b0;
            stage6_eol <= 1'b0;
            stage6_radial_x_q18 <= 21'sd0;
            stage6_radial_y_q18 <= 21'sd0;
            stage6_tangential_x_q18 <= 21'sd0;
            stage6_tangential_y_q18 <= 21'sd0;
            stage6_fx_q12 <= 24'sd0;
            stage6_fy_q12 <= 24'sd0;
            stage6_cx_q12 <= 24'sd0;
            stage6_cy_q12 <= 24'sd0;
            stage7_valid <= 1'b0;
            stage7_sof <= 1'b0;
            stage7_eol <= 1'b0;
            stage7_xd_q18 <= 21'sd0;
            stage7_yd_q18 <= 21'sd0;
            stage7_fx_q12 <= 24'sd0;
            stage7_fy_q12 <= 24'sd0;
            stage7_cx_q12 <= 24'sd0;
            stage7_cy_q12 <= 24'sd0;
            stage8_valid <= 1'b0;
            stage8_sof <= 1'b0;
            stage8_eol <= 1'b0;
            stage8_source_x_product <= 45'sd0;
            stage8_source_y_product <= 45'sd0;
            stage8_cx_q12 <= 24'sd0;
            stage8_cy_q12 <= 24'sd0;
            stage9_valid <= 1'b0;
            stage9_sof <= 1'b0;
            stage9_eol <= 1'b0;
            stage9_source_x_q19 <= 64'sd0;
            stage9_source_y_q19 <= 64'sd0;
            out_src_x_q19 <= 64'sd0;
            out_src_y_q19 <= 64'sd0;
            out_x0 <= 32'sd0;
            out_y0 <= 32'sd0;
            out_dx_q16 <= 16'd0;
            out_dy_q16 <= 16'd0;
            out_coord_valid <= 1'b0;
            out_valid <= 1'b0;
            out_sof <= 1'b0;
            out_eol <= 1'b0;
        end else begin
            // Stage 0: capture coordinate and select calibration at SOF.
            // The frame registers are updated in parallel so subsequent pixels
            // use the same frozen parameter set without a long SOF-controlled
            // combinational path.
            stage0_valid <= in_valid;
            stage0_sof <= in_valid && in_sof;
            stage0_eol <= in_valid && in_eol;
            stage0_u <= in_u;
            stage0_v <= in_v;
            if (in_valid && in_sof) begin
                stage0_fx_q19 <= cfg_fx_q19;
                stage0_fy_q19 <= cfg_fy_q19;
                stage0_cx_q19 <= cfg_cx_q19;
                stage0_cy_q19 <= cfg_cy_q19;
                stage0_inv_fx_q30 <= cfg_inv_fx_q30;
                stage0_inv_fy_q30 <= cfg_inv_fy_q30;
                stage0_k1_q28 <= cfg_k1_q28;
                stage0_k2_q28 <= cfg_k2_q28;
                stage0_p1_q28 <= cfg_p1_q28;
                stage0_p2_q28 <= cfg_p2_q28;
                frame_fx_q19 <= cfg_fx_q19;
                frame_fy_q19 <= cfg_fy_q19;
                frame_cx_q19 <= cfg_cx_q19;
                frame_cy_q19 <= cfg_cy_q19;
                frame_inv_fx_q30 <= cfg_inv_fx_q30;
                frame_inv_fy_q30 <= cfg_inv_fy_q30;
                frame_k1_q28 <= cfg_k1_q28;
                frame_k2_q28 <= cfg_k2_q28;
                frame_p1_q28 <= cfg_p1_q28;
                frame_p2_q28 <= cfg_p2_q28;
            end else begin
                stage0_fx_q19 <= frame_fx_q19;
                stage0_fy_q19 <= frame_fy_q19;
                stage0_cx_q19 <= frame_cx_q19;
                stage0_cy_q19 <= frame_cy_q19;
                stage0_inv_fx_q30 <= frame_inv_fx_q30;
                stage0_inv_fy_q30 <= frame_inv_fy_q30;
                stage0_k1_q28 <= frame_k1_q28;
                stage0_k2_q28 <= frame_k2_q28;
                stage0_p1_q28 <= frame_p1_q28;
                stage0_p2_q28 <= frame_p2_q28;
            end

            // Output stage: coordinate_split is the only combinational work
            // after the registered Q19 source coordinates.
            out_valid <= stage9_valid;
            out_sof <= stage9_valid && stage9_sof;
            out_eol <= stage9_valid && stage9_eol;
            if (stage9_valid) begin
                out_src_x_q19 <= stage9_source_x_q19;
                out_src_y_q19 <= stage9_source_y_q19;
                out_x0 <= split_x0;
                out_y0 <= split_y0;
                out_dx_q16 <= split_dx_q16;
                out_dy_q16 <= split_dy_q16;
                out_coord_valid <= split_coord_valid;
            end else begin
                out_src_x_q19 <= 64'sd0;
                out_src_y_q19 <= 64'sd0;
                out_x0 <= 32'sd0;
                out_y0 <= 32'sd0;
                out_dx_q16 <= 16'd0;
                out_dy_q16 <= 16'd0;
                out_coord_valid <= 1'b0;
            end

            // Stage 9: add the principal point after shifting the registered
            // focal product into Q19.
            stage9_valid <= stage8_valid;
            stage9_sof <= stage8_sof;
            stage9_eol <= stage8_eol;
            stage9_source_x_q19 <= source_x_q19;
            stage9_source_y_q19 <= source_y_q19;

            // Stage 8: isolate both focal multipliers.
            stage8_valid <= stage7_valid;
            stage8_sof <= stage7_sof;
            stage8_eol <= stage7_eol;
            stage8_source_x_product <= source_x_product;
            stage8_source_y_product <= source_y_product;
            stage8_cx_q12 <= stage7_cx_q12;
            stage8_cy_q12 <= stage7_cy_q12;

            // Stage 7: add radial and tangential components.
            stage7_valid <= stage6_valid;
            stage7_sof <= stage6_sof;
            stage7_eol <= stage6_eol;
            stage7_xd_q18 <= distorted_x_q18;
            stage7_yd_q18 <= distorted_y_q18;
            stage7_fx_q12 <= stage6_fx_q12;
            stage7_fy_q12 <= stage6_fy_q12;
            stage7_cx_q12 <= stage6_cx_q12;
            stage7_cy_q12 <= stage6_cy_q12;

            // Stage 6: add the two tangential terms per axis.
            stage6_valid <= stage5_valid;
            stage6_sof <= stage5_sof;
            stage6_eol <= stage5_eol;
            stage6_radial_x_q18 <= stage5_radial_x_q18;
            stage6_radial_y_q18 <= stage5_radial_y_q18;
            stage6_tangential_x_q18 <= tangential_x_q18;
            stage6_tangential_y_q18 <= tangential_y_q18;
            stage6_fx_q12 <= stage5_fx_q12;
            stage6_fy_q12 <= stage5_fy_q12;
            stage6_cx_q12 <= stage5_cx_q12;
            stage6_cy_q12 <= stage5_cy_q12;

            // Stage 5: second tangential multipliers and all original term
            // quantization points.
            stage5_valid <= stage4_valid;
            stage5_sof <= stage4_sof;
            stage5_eol <= stage4_eol;
            stage5_radial_x_q18 <= radial_x_q18;
            stage5_radial_y_q18 <= radial_y_q18;
            stage5_tangential_x_term1 <= tangential_x_term1;
            stage5_tangential_x_term2 <= tangential_x_term2;
            stage5_tangential_y_term1 <= tangential_y_term1;
            stage5_tangential_y_term2 <= tangential_y_term2;
            stage5_fx_q12 <= stage4_fx_q12;
            stage5_fy_q12 <= stage4_fy_q12;
            stage5_cx_q12 <= stage4_cx_q12;
            stage5_cy_q12 <= stage4_cy_q12;

            // Stage 4: first radial/tangential products and lossless bases.
            stage4_valid <= stage3_valid;
            stage4_sof <= stage3_sof;
            stage4_eol <= stage3_eol;
            stage4_radial_x_product <= radial_x_product;
            stage4_radial_y_product <= radial_y_product;
            stage4_p1_xy_product <= p1_xy_product;
            stage4_p2_xy_product <= p2_xy_product;
            stage4_tangential_x_base <= tangential_x_base;
            stage4_tangential_y_base <= tangential_y_base;
            stage4_p1_q18 <= stage3_p1_q18;
            stage4_p2_q18 <= stage3_p2_q18;
            stage4_fx_q12 <= stage3_fx_q12;
            stage4_fy_q12 <= stage3_fy_q12;
            stage4_cx_q12 <= stage3_cx_q12;
            stage4_cy_q12 <= stage3_cy_q12;

            stage3_valid <= stage2h_valid;
            stage3_sof <= stage2h_sof;
            stage3_eol <= stage2h_eol;
            stage3_x_q18 <= stage2h_x_q18;
            stage3_y_q18 <= stage2h_y_q18;
            stage3_x2_q18 <= stage2h_x2_q18;
            stage3_y2_q18 <= stage2h_y2_q18;
            stage3_xy_q18 <= stage2h_xy_q18;
            stage3_r2_q18 <= stage2h_r2_q18;
            stage3_radial_q18 <= radial_q18;
            stage3_p1_q18 <= stage2h_p1_q18;
            stage3_p2_q18 <= stage2h_p2_q18;
            stage3_fx_q12 <= stage2h_fx_q12;
            stage3_fy_q12 <= stage2h_fy_q12;
            stage3_cx_q12 <= stage2h_cx_q12;
            stage3_cy_q12 <= stage2h_cy_q12;

            stage2h_valid <= stage2_valid;
            stage2h_sof <= stage2_sof;
            stage2h_eol <= stage2_eol;
            stage2h_x_q18 <= stage2_x_q18;
            stage2h_y_q18 <= stage2_y_q18;
            stage2h_x2_q18 <= stage2_x2_q18;
            stage2h_y2_q18 <= stage2_y2_q18;
            stage2h_xy_q18 <= stage2_xy_q18;
            stage2h_r2_q18 <= stage2_r2_q18;
            stage2h_horner_t_q18 <= horner_t_q18;
            stage2h_p1_q18 <= stage2_p1_q18;
            stage2h_p2_q18 <= stage2_p2_q18;
            stage2h_fx_q12 <= stage2_fx_q12;
            stage2h_fy_q12 <= stage2_fy_q12;
            stage2h_cx_q12 <= stage2_cx_q12;
            stage2h_cy_q12 <= stage2_cy_q12;

            stage2_valid <= stage1_valid;
            stage2_sof <= stage1_sof;
            stage2_eol <= stage1_eol;
            stage2_x_q18 <= stage1_x_q18;
            stage2_y_q18 <= stage1_y_q18;
            stage2_x2_q18 <= x_squared_q18;
            stage2_y2_q18 <= y_squared_q18;
            stage2_xy_q18 <= xy_q18;
            stage2_r2_q18 <= radius_squared_q18;
            stage2_k1_q18 <= stage1_k1_q18;
            stage2_k2_q18 <= stage1_k2_q18;
            stage2_p1_q18 <= stage1_p1_q18;
            stage2_p2_q18 <= stage1_p2_q18;
            stage2_fx_q12 <= stage1_fx_q12;
            stage2_fy_q12 <= stage1_fy_q12;
            stage2_cx_q12 <= stage1_cx_q12;
            stage2_cy_q12 <= stage1_cy_q12;

            // Stage 1C: finish center subtraction and quantize the inverse
            // focal values before the normalized-coordinate multipliers.
            stage1c_valid <= stage0_valid;
            stage1c_sof <= stage0_sof;
            stage1c_eol <= stage0_eol;
            stage1c_centered_x_q12 <= centered_x_q12;
            stage1c_centered_y_q12 <= centered_y_q12;
            stage1c_inverse_fx_q24 <= inverse_fx_q24;
            stage1c_inverse_fy_q24 <= inverse_fy_q24;
            stage1c_k1_q28 <= stage0_k1_q28;
            stage1c_k2_q28 <= stage0_k2_q28;
            stage1c_p1_q28 <= stage0_p1_q28;
            stage1c_p2_q28 <= stage0_p2_q28;
            stage1c_fx_q19 <= stage0_fx_q19;
            stage1c_fy_q19 <= stage0_fy_q19;
            stage1c_cx_q19 <= stage0_cx_q19;
            stage1c_cy_q19 <= stage0_cy_q19;

            // Stage 1M: split each signed 23x26 multiplication at bit 18.
            // The two 18x18 p00 products map independently; the remaining
            // high-part products are small enough to avoid the old four-APM
            // cascade.
            stage1m_valid <= stage1c_valid;
            stage1m_sof <= stage1c_sof;
            stage1m_eol <= stage1c_eol;
            stage1m_x_p00 <= stage1c_centered_x_q12[17:0] *
                              stage1c_inverse_fx_q24[17:0];
            stage1m_x_p10 <= $signed(stage1c_centered_x_q12[22:18]) *
                              $signed({1'b0, stage1c_inverse_fx_q24[17:0]});
            stage1m_x_p01 <= $signed({1'b0, stage1c_centered_x_q12[17:0]}) *
                              $signed(stage1c_inverse_fx_q24[25:18]);
            stage1m_x_p11 <= $signed(stage1c_centered_x_q12[22:18]) *
                              $signed(stage1c_inverse_fx_q24[25:18]);
            stage1m_y_p00 <= stage1c_centered_y_q12[17:0] *
                              stage1c_inverse_fy_q24[17:0];
            stage1m_y_p10 <= $signed(stage1c_centered_y_q12[22:18]) *
                              $signed({1'b0, stage1c_inverse_fy_q24[17:0]});
            stage1m_y_p01 <= $signed({1'b0, stage1c_centered_y_q12[17:0]}) *
                              $signed(stage1c_inverse_fy_q24[25:18]);
            stage1m_y_p11 <= $signed(stage1c_centered_y_q12[22:18]) *
                              $signed(stage1c_inverse_fy_q24[25:18]);
            stage1m_k1_q28 <= stage1c_k1_q28;
            stage1m_k2_q28 <= stage1c_k2_q28;
            stage1m_p1_q28 <= stage1c_p1_q28;
            stage1m_p2_q28 <= stage1c_p2_q28;
            stage1m_fx_q19 <= stage1c_fx_q19;
            stage1m_fy_q19 <= stage1c_fy_q19;
            stage1m_cx_q19 <= stage1c_cx_q19;
            stage1m_cy_q19 <= stage1c_cy_q19;

            // Stage 1S: register the exact partial-product reconstruction
            // inputs before the final shift/saturate in Stage 1.
            stage1s_valid <= stage1m_valid;
            stage1s_sof <= stage1m_sof;
            stage1s_eol <= stage1m_eol;
            stage1s_x_p00 <= stage1m_x_p00;
            stage1s_x_cross_sum <= stage1m_x_cross_sum;
            stage1s_x_p11 <= stage1m_x_p11;
            stage1s_y_p00 <= stage1m_y_p00;
            stage1s_y_cross_sum <= stage1m_y_cross_sum;
            stage1s_y_p11 <= stage1m_y_p11;
            stage1s_k1_q28 <= stage1m_k1_q28;
            stage1s_k2_q28 <= stage1m_k2_q28;
            stage1s_p1_q28 <= stage1m_p1_q28;
            stage1s_p2_q28 <= stage1m_p2_q28;
            stage1s_fx_q19 <= stage1m_fx_q19;
            stage1s_fy_q19 <= stage1m_fy_q19;
            stage1s_cx_q19 <= stage1m_cx_q19;
            stage1s_cy_q19 <= stage1m_cy_q19;

            // Stage 1: complete normalized coordinate reconstruction and the
            // original coefficient/intrinsic format conversions.
            stage1_valid <= stage1s_valid;
            stage1_sof <= stage1s_sof;
            stage1_eol <= stage1s_eol;
            stage1_x_q18 <= saturate_s20($signed(normalized_x_product) >>> 18);
            stage1_y_q18 <= saturate_s20($signed(normalized_y_product) >>> 18);
            stage1_k1_q18 <= saturate_s20(stage1s_k1_q28 >>> 10);
            stage1_k2_q18 <= saturate_s20(stage1s_k2_q28 >>> 10);
            stage1_p1_q18 <= saturate_s20(stage1s_p1_q28 >>> 10);
            stage1_p2_q18 <= saturate_s20(stage1s_p2_q28 >>> 10);
            stage1_fx_q12 <= saturate_s24(stage1s_fx_q19 >>> 7);
            stage1_fy_q12 <= saturate_s24(stage1s_fy_q19 >>> 7);
            stage1_cx_q12 <= saturate_s24(stage1s_cx_q19 >>> 7);
            stage1_cy_q12 <= saturate_s24(stage1s_cy_q19 >>> 7);
        end
    end
endmodule

`timescale 1ns / 1ps

// Brown map applied after homography in ideal Q16.16 pixel space.
// Calibration coordinates follow OpenCV's normalized camera convention:
//   x=(u-cx)/fx, y=(v-cy)/fy.
// Coefficients are from calibration.json, quantized to signed Q20. The k3
// branch is independently pipelined for ten arithmetic stages and held
// together under downstream backpressure.
module fractional_brown_mapper (
    input  wire                clk,
    input  wire                rstn,
    input  wire                s_valid,
    output wire                s_ready,
    input  wire signed [31:0]  s_sx,
    input  wire signed [31:0]  s_sy,
    input  wire                s_geometry_valid,
    input  wire [19:0]         s_pixel_id,
    input  wire [31:0]         s_frame_id,
    input  wire [15:0]         s_param_version,
    input  wire                s_sof,
    input  wire                s_eol,
    input  wire                s_eof,
    output reg                 m_valid,
    input  wire                m_ready,
    output reg signed [31:0]   m_sx,
    output reg signed [31:0]   m_sy,
    output reg                 m_geometry_valid,
    output reg [19:0]          m_pixel_id,
    output reg [31:0]          m_frame_id,
    output reg [15:0]          m_param_version,
    output reg                 m_sof,
    output reg                 m_eol,
    output reg                 m_eof
);
    // calibration.json (2026-10-26), represented as Q16.16 pixels and Q30
    // reciprocals. These values use the calibrated principal point/focal
    // lengths rather than the old (640,360), 512-pixel normalization.
    localparam signed [31:0] CX_Q16 = 32'sd39536083;
    localparam signed [31:0] CY_Q16 = 32'sd23190770;
    localparam signed [31:0] FX_Q16 = 32'sd55717096;
    localparam signed [31:0] FY_Q16 = 32'sd55958233;
    localparam signed [31:0] INV_FX_Q30 = 32'sd1262965;
    localparam signed [31:0] INV_FY_Q30 = 32'sd1257523;

    // k1=-0.4147728667, k2=+0.2415032890, k3=-0.0889511214,
    // p1=+0.0013237123, p2=+0.0000991201.
    localparam signed [20:0] K1_Q20 = -21'sd434921;
    localparam signed [20:0] K2_Q20 =  21'sd253235;
    localparam signed [20:0] K3_Q20 = -21'sd93209;
    localparam signed [20:0] P1_Q20 =  21'sd1388;
    localparam signed [20:0] P2_Q20 =  21'sd104;

    localparam integer META_WIDTH = 71;
    localparam signed [32:0] MAX_DELTA_Q16 = 33'sd134217728;
    wire advance = rstn && (!m_valid || m_ready);
    assign s_ready = advance;

    wire signed [32:0] dx_in = $signed({s_sx[31], s_sx}) - $signed(CX_Q16);
    wire signed [32:0] dy_in = $signed({s_sy[31], s_sy}) - $signed(CY_Q16);
    wire input_in_range = dx_in >= -MAX_DELTA_Q16 && dx_in <= MAX_DELTA_Q16 &&
        dy_in >= -MAX_DELTA_Q16 && dy_in <= MAX_DELTA_Q16;

    reg [15:0] valid_pipe;
    reg [META_WIDTH-1:0] meta [0:15];
    reg geometry [0:10];
    wire [19:0] debug_y8_pixel_id /* synthesis PAP_MARK_DEBUG="true" */ = meta[8][70:51];
    wire [19:0] debug_y10_pixel_id /* synthesis PAP_MARK_DEBUG="true" */ = meta[10][70:51];
    wire [19:0] debug_mapped_pixel_id /* synthesis PAP_MARK_DEBUG="true" */ = meta[11][70:51];

    // S0: original Q16.16 coordinates and principal-point-relative offsets.
    reg signed [31:0] x0, y0;
    reg signed [32:0] dx0;
    reg signed [32:0] dy0 /* synthesis PAP_MARK_DEBUG="true" */;
    // S1: OpenCV normalized coordinates, Q16.16.
    reg signed [31:0] xn1, yn1;
    reg signed [31:0] x1, y1;
    // S2: normalized square/cross products, raw Q32.32.
    reg signed [63:0] xx2, yy2, xy2;
    reg signed [31:0] x2, y2;
    reg signed [31:0] xn2, yn2;
    // S3: normalized square/cross terms and r^2, Q16.16.
    reg signed [31:0] xx3, yy3, xy3, radius2_3;
    reg signed [31:0] x3, y3;
    reg signed [31:0] xn3, yn3;
    // S4: r^4, k1*r^2, and tangential-polynomial arguments.
    reg signed [31:0] radius4_4, k1_radius2_4;
    reg signed [32:0] tang_x_arg4, tang_y_arg4;
    reg signed [31:0] xy4, x4, y4;
    reg signed [31:0] xn4, yn4;
    // S5: k2*r^4 and Q16.16 tangential products.
    reg signed [31:0] k1_radius2_5, k2_radius4_5;
    reg signed [31:0] p1_xy5, p2_x5, p1_y5, p2_xy5;
    reg signed [31:0] xn5, yn5, x5, y5;
    // S6: radial gain Q20 and tangential displacement in normalized Q16.16.
    reg signed [31:0] gain6, tang_x6, tang_y6;
    reg signed [31:0] xn6, yn6, x6, y6;
    // S7: radial normalized displacement Q16.16.
    reg signed [31:0] radial_x7, radial_y7;
    reg signed [31:0] tang_x7, tang_y7, x7, y7;
    // S8: combined normalized displacement Q16.16.
    reg signed [31:0] total_x8;
    reg signed [31:0] total_y8 /* synthesis PAP_MARK_DEBUG="true" */;
    reg [31:0] total_y_magnitude8;
    reg signed [31:0] x8, y8;
    // S9: unsigned Y pixel displacement product; X retains its prior stage.
    reg signed [31:0] correction_x9;
    reg [63:0] correction_y_magnitude_product9;
    reg correction_y_negative9;
    reg signed [31:0] x9;
    reg signed [31:0] y9;
    // S10: restore the signed Y displacement after the unsigned product.
    reg signed [31:0] correction_x10;
    reg signed [31:0] correction_y10 /* synthesis PAP_MARK_DEBUG="true" */;
    reg signed [31:0] x10;
    reg signed [31:0] y10 /* synthesis PAP_MARK_DEBUG="true" */;
    // S11: mapped output coordinates and final geometry validity.
    reg signed [63:0] mapped_x11;
    reg signed [63:0] mapped_y11 /* synthesis PAP_MARK_DEBUG="true" */;
    reg geometry11 /* synthesis PAP_MARK_DEBUG="true" */;

    // K3-only side pipeline: ten arithmetic stages expanded to twelve stages
    // after timing showed the full-width r^6 multiplier needed decomposition.
    reg [31:0] radius2_k3_4, radius4_k3_4;
    reg signed [31:0] xn_k3_4, yn_k3_4;
    reg signed [31:0] xn_k3_5, yn_k3_5, xn_k3_6, yn_k3_6;
    reg signed [31:0] xn_k3_7, yn_k3_7, xn_k3_8, yn_k3_8;
    reg signed [31:0] xn_k3_9, yn_k3_9, xn_k3_10, yn_k3_10;
    reg [31:0] r6_p00_5, r6_p01_5, r6_p10_5, r6_p11_5;
    reg [63:0] r6_low_sum6, r6_high_sum6;
    reg [63:0] r6_raw7;
    reg [31:0] r6_q16_8;
    reg signed [53:0] k3_product9;
    reg signed [37:0] k3_term10;
    reg signed [63:0] k3_dx_product11, k3_dy_product11;
    reg signed [31:0] k3_dx_norm12, k3_dy_norm12;
    reg [31:0] k3_dx_mag13, k3_dy_mag13;
    reg k3_dx_neg13, k3_dy_neg13;
    reg [63:0] k3_dx_pixel_product14, k3_dy_pixel_product14;
    reg k3_dx_neg14, k3_dy_neg14;
    reg signed [31:0] k3_correction_x15, k3_correction_y15;
    reg signed [63:0] mapped_x12, mapped_y12, mapped_x13, mapped_y13, mapped_x14, mapped_y14, mapped_x15, mapped_y15;
    reg geometry12, geometry13, geometry14, geometry15;
    reg [META_WIDTH-1:0] meta12, meta13, meta14, meta15;

    wire signed [64:0] x_norm_product = $signed(dx0) * $signed(INV_FX_Q30);
    wire signed [64:0] y_norm_product = $signed(dy0) * $signed(INV_FY_Q30);
    wire signed [31:0] xn1_next = x_norm_product >>> 30;
    wire signed [31:0] yn1_next = y_norm_product >>> 30;

    wire signed [63:0] xx2_next = $signed(xn1) * $signed(xn1);
    wire signed [63:0] yy2_next = $signed(yn1) * $signed(yn1);
    wire signed [63:0] xy2_next = $signed(xn1) * $signed(yn1);
    wire signed [63:0] radius2_raw3 = $signed(xx2) + $signed(yy2);
    wire signed [31:0] radius2_3_next = radius2_raw3 >>> 16;
    wire signed [31:0] xx3_next = xx2 >>> 16;
    wire signed [31:0] yy3_next = yy2 >>> 16;
    wire signed [31:0] xy3_next = xy2 >>> 16;

    // The accepted input window bounds each normalized coordinate to about
    // +/-2.41 Q16.16. Therefore r^2 is nonnegative and below 12 Q16.16, which
    // fits in signed 21 bits. Keeping the square at this proven width avoids
    // a 32x32 DSP cascade on the S3->S4 critical path.
    wire signed [41:0] radius4_product =
        $signed(radius2_3[20:0]) * $signed(radius2_3[20:0]);
    wire signed [63:0] k1_radius2_product = $signed(radius2_3) * $signed(K1_Q20);
    wire signed [32:0] tang_x_arg4_next = $signed({radius2_3[31], radius2_3}) +
        ($signed({xx3[31], xx3}) <<< 1);
    wire signed [32:0] tang_y_arg4_next = $signed({radius2_3[31], radius2_3}) +
        ($signed({yy3[31], yy3}) <<< 1);
    wire signed [31:0] radius4_4_next = radius4_product >>> 16;
    wire signed [31:0] k1_radius2_4_next = k1_radius2_product >>> 16;

    wire signed [63:0] k2_radius4_product = $signed(radius4_4) * $signed(K2_Q20);
    wire signed [63:0] p1_xy_product = $signed(xy4) * $signed(P1_Q20);
    wire signed [63:0] p2_x_product = $signed(tang_x_arg4) * $signed(P2_Q20);
    wire signed [63:0] p1_y_product = $signed(tang_y_arg4) * $signed(P1_Q20);
    wire signed [63:0] p2_xy_product = $signed(xy4) * $signed(P2_Q20);
    wire signed [31:0] k2_radius4_5_next = k2_radius4_product >>> 16;
    wire signed [31:0] p1_xy5_next = p1_xy_product >>> 20;
    wire signed [31:0] p2_x5_next = p2_x_product >>> 20;
    wire signed [31:0] p1_y5_next = p1_y_product >>> 20;
    wire signed [31:0] p2_xy5_next = p2_xy_product >>> 20;

    wire signed [31:0] gain6_next = k1_radius2_5 + k2_radius4_5;
    wire signed [31:0] tang_x6_next = ($signed(p1_xy5) <<< 1) + p2_x5;
    wire signed [31:0] tang_y6_next = p1_y5 + ($signed(p2_xy5) <<< 1);

    wire signed [63:0] radial_x_product = $signed(xn6) * $signed(gain6);
    wire signed [63:0] radial_y_product = $signed(yn6) * $signed(gain6);
    wire signed [31:0] radial_x7_next = radial_x_product >>> 20;
    wire signed [31:0] radial_y7_next = radial_y_product >>> 20;
    wire signed [31:0] total_x8_next = radial_x7 + tang_x7;
    wire signed [31:0] total_y8_next = radial_y7 + tang_y7;
    wire signed [63:0] correction_x_product = $signed(total_x8) * $signed(FX_Q16);
    // The board capture showed the signed Y constant multiplier returning
    // the correct low bits but an extra 0x01800000 for negative total_y8.
    // Keep the multiplier unsigned. Its absolute input, product and sign
    // restoration occupy separate existing/new pipeline stages.
    wire [31:0] total_y_magnitude8_next = total_y8_next[31]
        ? (~$unsigned(total_y8_next) + 32'd1) : $unsigned(total_y8_next);
    wire [63:0] correction_y_magnitude_product9_next =
        $unsigned(total_y_magnitude8) * $unsigned(FY_Q16);
    // For negative values, arithmetic right shift rounds toward -infinity:
    // -(q + (remainder != 0)) == ~q + (remainder == 0).
    wire [31:0] correction_y_floor10 = correction_y_magnitude_product9[47:16];
    wire [31:0] correction_y_negative10 = ~correction_y_floor10 +
        {31'd0, correction_y_magnitude_product9[15:0] == 16'd0};
    wire signed [31:0] correction_x9_next = correction_x_product >>> 16;
    wire signed [31:0] correction_y10_next = correction_y_negative9
        ? $signed(correction_y_negative10) : $signed(correction_y_floor10);
    wire signed [63:0] mapped_x11_next = $signed(x10) + $signed(correction_x10);
    wire signed [63:0] mapped_y11_next = $signed(y10) + $signed(correction_y10);
    wire [31:0] r6_p00_5_next = $unsigned(radius4_k3_4[15:0]) * $unsigned(radius2_k3_4[15:0]);
    wire [31:0] r6_p01_5_next = $unsigned(radius4_k3_4[31:16]) * $unsigned(radius2_k3_4[15:0]);
    wire [31:0] r6_p10_5_next = $unsigned(radius4_k3_4[15:0]) * $unsigned(radius2_k3_4[31:16]);
    wire [31:0] r6_p11_5_next = $unsigned(radius4_k3_4[31:16]) * $unsigned(radius2_k3_4[31:16]);
    wire [63:0] r6_low_sum6_next = {32'd0, r6_p00_5} + {16'd0, r6_p01_5, 16'd0};
    wire [63:0] r6_high_sum6_next = {16'd0, r6_p10_5, 16'd0} + {r6_p11_5, 32'd0};
    wire [63:0] r6_raw7_next = r6_low_sum6 + r6_high_sum6;
    wire [31:0] r6_q16_8_next = r6_raw7[47:16];
    wire signed [53:0] k3_product9_next = $signed(K3_Q20) * $signed({1'b0, r6_q16_8});
    wire signed [37:0] k3_term10_next = k3_product9 >>> 16;
    wire signed [63:0] k3_dx_product11_next = $signed(xn_k3_10) * $signed(k3_term10);
    wire signed [63:0] k3_dy_product11_next = $signed(yn_k3_10) * $signed(k3_term10);
    wire signed [31:0] k3_dx_norm12_next = k3_dx_product11 >>> 20;
    wire signed [31:0] k3_dy_norm12_next = k3_dy_product11 >>> 20;
    wire [31:0] k3_dx_mag13_next = k3_dx_norm12[31] ? (~$unsigned(k3_dx_norm12) + 32'd1) : $unsigned(k3_dx_norm12);
    wire [31:0] k3_dy_mag13_next = k3_dy_norm12[31] ? (~$unsigned(k3_dy_norm12) + 32'd1) : $unsigned(k3_dy_norm12);
    wire [63:0] k3_dx_pixel_product14_next = $unsigned(k3_dx_mag13) * $unsigned(FX_Q16);
    wire [63:0] k3_dy_pixel_product14_next = $unsigned(k3_dy_mag13) * $unsigned(FY_Q16);
    wire [31:0] k3_dx_floor15 = k3_dx_pixel_product14[47:16];
    wire [31:0] k3_dy_floor15 = k3_dy_pixel_product14[47:16];
    wire signed [31:0] k3_correction_x15_next = k3_dx_neg14
        ? $signed(~k3_dx_floor15 + {31'd0, k3_dx_pixel_product14[15:0] == 16'd0})
        : $signed(k3_dx_floor15);
    wire signed [31:0] k3_correction_y15_next = k3_dy_neg14
        ? $signed(~k3_dy_floor15 + {31'd0, k3_dy_pixel_product14[15:0] == 16'd0})
        : $signed(k3_dy_floor15);
    wire signed [63:0] mapped_x16_next = $signed(mapped_x15) + $signed(k3_correction_x15);
    wire signed [63:0] mapped_y16_next = $signed(mapped_y15) + $signed(k3_correction_y15);
    wire output_in_range16 = mapped_x16_next >= -64'sd2147483648 &&
        mapped_x16_next <= 64'sd2147483647 &&
        mapped_y16_next >= -64'sd2147483648 &&
        mapped_y16_next <= 64'sd2147483647;
    wire output_in_range11 = mapped_x11_next >= -64'sd2147483648 &&
        mapped_x11_next <= 64'sd2147483647 &&
        mapped_y11_next >= -64'sd2147483648 &&
        mapped_y11_next <= 64'sd2147483647;

    always @(posedge clk) begin
        if (!rstn) begin
            valid_pipe <= 16'b0;
            m_valid <= 1'b0;
            m_sx <= 0; m_sy <= 0; m_geometry_valid <= 0;
            m_pixel_id <= 0; m_frame_id <= 0; m_param_version <= 0;
            m_sof <= 0; m_eol <= 0; m_eof <= 0;
        end else if (advance) begin
            valid_pipe <= {valid_pipe[14:0], s_valid};
            m_valid <= valid_pipe[15];
            if (valid_pipe[15]) begin
                m_sx <= geometry15 && output_in_range16 ? mapped_x16_next[31:0] : 32'sd0;
                m_sy <= geometry15 && output_in_range16 ? mapped_y16_next[31:0] : 32'sd0;
                m_geometry_valid <= geometry15 && output_in_range16;
                {m_pixel_id, m_frame_id, m_param_version, m_sof, m_eol, m_eof} <= meta15;
            end

            if (valid_pipe[14]) begin
                geometry15 <= geometry14;
                mapped_x15 <= mapped_x14; mapped_y15 <= mapped_y14;
                meta15 <= meta14;
                k3_correction_x15 <= k3_correction_x15_next;
                k3_correction_y15 <= k3_correction_y15_next;
            end
            if (valid_pipe[13]) begin
                geometry14 <= geometry13;
                mapped_x14 <= mapped_x13; mapped_y14 <= mapped_y13;
                meta14 <= meta13;
                k3_dx_pixel_product14 <= k3_dx_pixel_product14_next;
                k3_dy_pixel_product14 <= k3_dy_pixel_product14_next;
                k3_dx_neg14 <= k3_dx_neg13; k3_dy_neg14 <= k3_dy_neg13;
            end
            if (valid_pipe[12]) begin
                geometry13 <= geometry12;
                mapped_x13 <= mapped_x12; mapped_y13 <= mapped_y12;
                meta13 <= meta12;
                k3_dx_mag13 <= k3_dx_mag13_next; k3_dy_mag13 <= k3_dy_mag13_next;
                k3_dx_neg13 <= k3_dx_norm12[31]; k3_dy_neg13 <= k3_dy_norm12[31];
            end
            if (valid_pipe[11]) begin
                geometry12 <= geometry11;
                mapped_x12 <= mapped_x11; mapped_y12 <= mapped_y11;
                meta12 <= meta[11];
                k3_dx_norm12 <= k3_dx_norm12_next; k3_dy_norm12 <= k3_dy_norm12_next;
            end
            if (valid_pipe[10]) begin
                k3_dx_product11 <= k3_dx_product11_next; k3_dy_product11 <= k3_dy_product11_next;
            end
            if (valid_pipe[9]) begin
                k3_term10 <= k3_term10_next;
                xn_k3_10 <= xn_k3_9; yn_k3_10 <= yn_k3_9;
            end
            if (valid_pipe[8]) begin
                k3_product9 <= k3_product9_next;
                xn_k3_9 <= xn_k3_8; yn_k3_9 <= yn_k3_8;
            end
            if (valid_pipe[7]) begin
                r6_q16_8 <= r6_q16_8_next;
                xn_k3_8 <= xn_k3_7; yn_k3_8 <= yn_k3_7;
            end
            if (valid_pipe[6]) begin
                r6_raw7 <= r6_raw7_next;
                xn_k3_7 <= xn_k3_6; yn_k3_7 <= yn_k3_6;
            end
            if (valid_pipe[5]) begin
                r6_low_sum6 <= r6_low_sum6_next;
                r6_high_sum6 <= r6_high_sum6_next;
                xn_k3_6 <= xn_k3_5; yn_k3_6 <= yn_k3_5;
            end
            if (valid_pipe[4]) begin
                r6_p00_5 <= r6_p00_5_next; r6_p01_5 <= r6_p01_5_next;
                r6_p10_5 <= r6_p10_5_next; r6_p11_5 <= r6_p11_5_next;
                xn_k3_5 <= xn_k3_4; yn_k3_5 <= yn_k3_4;
            end
            if (valid_pipe[3]) begin
                radius2_k3_4 <= $unsigned(radius2_3);
                radius4_k3_4 <= $unsigned(radius4_4_next);
                xn_k3_4 <= xn3; yn_k3_4 <= yn3;
            end

            if (valid_pipe[10]) begin
                geometry11 <= geometry[10] && output_in_range11;
                mapped_x11 <= mapped_x11_next;
                mapped_y11 <= mapped_y11_next;
                meta[11] <= meta[10];
            end
            if (valid_pipe[9]) begin
                geometry[10] <= geometry[9];
                correction_x10 <= correction_x9;
                correction_y10 <= correction_y10_next;
                x10 <= x9; y10 <= y9;
                meta[10] <= meta[9];
            end
            if (valid_pipe[8]) begin
                geometry[9] <= geometry[8];
                correction_x9 <= correction_x9_next;
                correction_y_magnitude_product9 <= correction_y_magnitude_product9_next;
                correction_y_negative9 <= total_y8[31];
                x9 <= x8; y9 <= y8;
                meta[9] <= meta[8];
            end
            if (valid_pipe[7]) begin
                geometry[8] <= geometry[7];
                total_x8 <= total_x8_next;
                total_y8 <= total_y8_next;
                total_y_magnitude8 <= total_y_magnitude8_next;
                x8 <= x7; y8 <= y7;
                meta[8] <= meta[7];
            end
            if (valid_pipe[6]) begin
                geometry[7] <= geometry[6];
                radial_x7 <= radial_x7_next;
                radial_y7 <= radial_y7_next;
                tang_x7 <= tang_x6; tang_y7 <= tang_y6;
                x7 <= x6; y7 <= y6;
                meta[7] <= meta[6];
            end
            if (valid_pipe[5]) begin
                geometry[6] <= geometry[5];
                gain6 <= gain6_next;
                tang_x6 <= tang_x6_next; tang_y6 <= tang_y6_next;
                xn6 <= xn5; yn6 <= yn5;
                x6 <= x5; y6 <= y5;
                meta[6] <= meta[5];
            end
            if (valid_pipe[4]) begin
                geometry[5] <= geometry[4];
                k1_radius2_5 <= k1_radius2_4;
                k2_radius4_5 <= k2_radius4_5_next;
                p1_xy5 <= p1_xy5_next; p2_x5 <= p2_x5_next;
                p1_y5 <= p1_y5_next; p2_xy5 <= p2_xy5_next;
                xn5 <= xn4; yn5 <= yn4;
                x5 <= x4; y5 <= y4;
                meta[5] <= meta[4];
            end
            if (valid_pipe[3]) begin
                geometry[4] <= geometry[3];
                radius4_4 <= radius4_4_next;
                k1_radius2_4 <= k1_radius2_4_next;
                tang_x_arg4 <= tang_x_arg4_next;
                tang_y_arg4 <= tang_y_arg4_next;
                xy4 <= xy3;
                xn4 <= xn3; yn4 <= yn3;
                x4 <= x3; y4 <= y3;
                meta[4] <= meta[3];
            end
            if (valid_pipe[2]) begin
                geometry[3] <= geometry[2];
                radius2_3 <= radius2_3_next;
                xx3 <= xx3_next; yy3 <= yy3_next; xy3 <= xy3_next;
                xn3 <= xn2; yn3 <= yn2;
                x3 <= x2; y3 <= y2;
                meta[3] <= meta[2];
            end
            if (valid_pipe[1]) begin
                geometry[2] <= geometry[1];
                xx2 <= xx2_next; yy2 <= yy2_next; xy2 <= xy2_next;
                xn2 <= xn1; yn2 <= yn1;
                x2 <= x1; y2 <= y1;
                meta[2] <= meta[1];
            end
            if (valid_pipe[0]) begin
                geometry[1] <= geometry[0];
                xn1 <= xn1_next; yn1 <= yn1_next;
                x1 <= x0; y1 <= y0;
                meta[1] <= meta[0];
            end
            if (s_valid) begin
                geometry[0] <= s_geometry_valid && input_in_range;
                meta[0] <= {s_pixel_id, s_frame_id, s_param_version, s_sof, s_eol, s_eof};
                x0 <= input_in_range ? s_sx : 32'sd0;
                y0 <= input_in_range ? s_sy : 32'sd0;
                dx0 <= input_in_range ? dx_in : 33'sd0;
                dy0 <= input_in_range ? dy_in : 33'sd0;
            end
        end
    end
endmodule

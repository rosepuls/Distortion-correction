`timescale 1ns / 1ps

// Separable Catmull-Rom RGB interpolation over a row-major 4x4 stencil.
// Coordinates are Q0.16, weights Q2.14, horizontal sums Q14 and vertical
// accumulators Q28. Eight elastic stages isolate coordinate squares, cubes,
// Q16.16 weight formation, weight quantization, horizontal pair products,
// horizontal pair sums, vertical products, and output rounding.
module pipelined_catmull_rom_interpolator (
    input  wire         clk,
    input  wire         rstn,
    input  wire         s_valid,
    output wire         s_ready,
    input  wire [511:0] s_samples,
    input  wire [15:0]  s_fx,
    input  wire [15:0]  s_fy,
    input  wire [15:0]  s_neighbor_valid,
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
    reg v0, v1, v2, v3, v4, v5, v6;
    wire r7 = !m_valid || m_ready;
    wire r6 = !v6 || r7;
    wire r5 = !v5 || r6;
    wire r4 = !v4 || r5;
    wire r3 = !v3 || r4;
    wire r2 = !v2 || r3;
    wire r1 = !v1 || r2;
    wire r0 = !v0 || r1;
    assign s_ready = rstn && r0;

    reg [511:0] samples_0, samples_1, samples_2, samples_3;
    reg [15:0] fx_0, fy_0, t2x_0, t2y_0;
    reg [15:0] fx_1, fy_1, t2x_1, t2y_1, t3x_1, t3y_1;
    reg [127:0] weights_x_q16_2, weights_y_q16_2;
    reg [63:0] wx_3, wy_3, wy_4, wy_5;
    reg [51:0] horizontal_pairs_4 [0:11];
    reg signed [26:0] horizontal_5 [0:11];
    reg signed [42:0] vertical_product_6 [0:11];
    reg [87:0] meta_0, meta_1, meta_2, meta_3, meta_4, meta_5, meta_6;

    wire [31:0] fx_square = {16'd0, s_fx} * {16'd0, s_fx};
    wire [31:0] fy_square = {16'd0, s_fy} * {16'd0, s_fy};
    wire [31:0] fx_cube_0 = {16'd0, t2x_0} * {16'd0, fx_0};
    wire [31:0] fy_cube_0 = {16'd0, t2y_0} * {16'd0, fy_0};

    function automatic signed [15:0] q16_to_q14;
        input signed [31:0] value;
        reg signed [32:0] magnitude;
        begin
            if (value < 0) begin
                magnitude = -{value[31], value};
                q16_to_q14 = -((magnitude + 33'sd2) >>> 2);
            end else
                q16_to_q14 = (value + 32'sd2) >>> 2;
        end
    endfunction

    function automatic [127:0] make_catmull_weights_q16;
        input [15:0] t;
        input [15:0] t2;
        input [15:0] t3;
        reg signed [31:0] ts, t2s, t3s;
        reg signed [31:0] w0_q16, w1_q16, w2_q16, w3_q16;
        begin
            ts = {16'd0, t};
            t2s = {16'd0, t2};
            t3s = {16'd0, t3};
            w0_q16 = -(ts >>> 1) + t2s - (t3s >>> 1);
            w1_q16 = 32'sd65536 - ((t2s * 32'sd5) >>> 1)
                     + ((t3s * 32'sd3) >>> 1);
            w2_q16 = (ts >>> 1) + (t2s <<< 1)
                     - ((t3s * 32'sd3) >>> 1);
            w3_q16 = -(t2s >>> 1) + (t3s >>> 1);
            make_catmull_weights_q16 = {w3_q16, w2_q16, w1_q16, w0_q16};
        end
    endfunction

    function automatic [63:0] quantize_catmull_weights;
        input [127:0] weights_q16;
        reg signed [31:0] w0_q16, w1_q16, w2_q16, w3_q16;
        reg signed [15:0] q0, q1, q2, q3;
        begin
            w0_q16 = weights_q16[31:0];
            w1_q16 = weights_q16[63:32];
            w2_q16 = weights_q16[95:64];
            w3_q16 = weights_q16[127:96];
            q0 = q16_to_q14(w0_q16);
            q2 = q16_to_q14(w2_q16);
            q3 = q16_to_q14(w3_q16);
            q1 = 16'sd16384 - q0 - q2 - q3;
            quantize_catmull_weights = {q3, q2, q1, q0};
        end
    endfunction

    function automatic [51:0] weighted_four_pairs;
        input [7:0] p0, p1, p2, p3;
        input signed [15:0] w0, w1, w2, w3;
        reg signed [24:0] product0, product1, product2, product3;
        reg signed [25:0] pair01, pair23;
        begin
            product0 = $signed({1'b0, p0}) * w0;
            product1 = $signed({1'b0, p1}) * w1;
            product2 = $signed({1'b0, p2}) * w2;
            product3 = $signed({1'b0, p3}) * w3;
            pair01 = product0 + product1;
            pair23 = product2 + product3;
            weighted_four_pairs = {pair23, pair01};
        end
    endfunction

    function automatic [7:0] round_saturate_q28;
        input signed [44:0] value;
        reg signed [45:0] rounded;
        begin
            if (value <= 0)
                round_saturate_q28 = 8'd0;
            else begin
                rounded = (value + 45'sd134217728) >>> 28;
                if (rounded > 255)
                    round_saturate_q28 = 8'd255;
                else
                    round_saturate_q28 = rounded[7:0];
            end
        end
    endfunction

    wire signed [44:0] sum_red = vertical_product_6[0] + vertical_product_6[1]
                                + vertical_product_6[2] + vertical_product_6[3];
    wire signed [44:0] sum_green = vertical_product_6[4] + vertical_product_6[5]
                                  + vertical_product_6[6] + vertical_product_6[7];
    wire signed [44:0] sum_blue = vertical_product_6[8] + vertical_product_6[9]
                                 + vertical_product_6[10] + vertical_product_6[11];
    wire [7:0] out_red = round_saturate_q28(sum_red);
    wire [7:0] out_green = round_saturate_q28(sum_green);
    wire [7:0] out_blue = round_saturate_q28(sum_blue);

    integer row_index, channel_index;
    always @(posedge clk) begin
        if (!rstn) begin
            v0 <= 1'b0; v1 <= 1'b0; v2 <= 1'b0; v3 <= 1'b0;
            v4 <= 1'b0; v5 <= 1'b0; v6 <= 1'b0;
            m_valid <= 1'b0;
            m_pixel <= 32'd0; m_geometry_valid <= 1'b0;
            m_pixel_id <= 20'd0; m_frame_id <= 32'd0;
            m_param_version <= 16'd0;
            m_sof <= 1'b0; m_eol <= 1'b0; m_eof <= 1'b0;
            samples_0 <= 512'd0; samples_1 <= 512'd0;
            samples_2 <= 512'd0; samples_3 <= 512'd0;
            fx_0 <= 16'd0; fy_0 <= 16'd0;
            t2x_0 <= 16'd0; t2y_0 <= 16'd0;
            fx_1 <= 16'd0; fy_1 <= 16'd0;
            t2x_1 <= 16'd0; t2y_1 <= 16'd0;
            t3x_1 <= 16'd0; t3y_1 <= 16'd0;
            weights_x_q16_2 <= 128'd0; weights_y_q16_2 <= 128'd0;
            wx_3 <= 64'd0; wy_3 <= 64'd0; wy_4 <= 64'd0; wy_5 <= 64'd0;
            meta_0 <= 88'd0; meta_1 <= 88'd0; meta_2 <= 88'd0;
            meta_3 <= 88'd0; meta_4 <= 88'd0; meta_5 <= 88'd0;
            meta_6 <= 88'd0;
        end else begin
            if (r0) begin
                v0 <= s_valid;
                if (s_valid) begin
                    samples_0 <= s_samples;
                    fx_0 <= s_fx; fy_0 <= s_fy;
                    t2x_0 <= fx_square[31:16];
                    t2y_0 <= fy_square[31:16];
                    meta_0 <= {s_geometry_valid, s_neighbor_valid,
                        s_pixel_id, s_frame_id, s_param_version,
                        s_sof, s_eol, s_eof};
                end
            end
            if (r1) begin
                v1 <= v0;
                if (v0) begin
                    samples_1 <= samples_0;
                    fx_1 <= fx_0; fy_1 <= fy_0;
                    t2x_1 <= t2x_0; t2y_1 <= t2y_0;
                    t3x_1 <= fx_cube_0[31:16];
                    t3y_1 <= fy_cube_0[31:16];
                    meta_1 <= meta_0;
                end
            end
            if (r2) begin
                v2 <= v1;
                if (v1) begin
                    samples_2 <= samples_1;
                    weights_x_q16_2 <= make_catmull_weights_q16(fx_1, t2x_1, t3x_1);
                    weights_y_q16_2 <= make_catmull_weights_q16(fy_1, t2y_1, t3y_1);
                    meta_2 <= meta_1;
                end
            end
            if (r3) begin
                v3 <= v2;
                if (v2) begin
                    samples_3 <= samples_2;
                    wx_3 <= quantize_catmull_weights(weights_x_q16_2);
                    wy_3 <= quantize_catmull_weights(weights_y_q16_2);
                    meta_3 <= meta_2;
                end
            end
            if (r4) begin
                v4 <= v3;
                if (v3) begin
                    for (row_index = 0; row_index < 4; row_index = row_index + 1) begin
                        horizontal_pairs_4[row_index*3] <= weighted_four_pairs(
                            samples_3[(row_index*4+0)*32+24 +: 8],
                            samples_3[(row_index*4+1)*32+24 +: 8],
                            samples_3[(row_index*4+2)*32+24 +: 8],
                            samples_3[(row_index*4+3)*32+24 +: 8],
                            $signed(wx_3[15:0]), $signed(wx_3[31:16]),
                            $signed(wx_3[47:32]), $signed(wx_3[63:48]));
                        horizontal_pairs_4[row_index*3+1] <= weighted_four_pairs(
                            samples_3[(row_index*4+0)*32+16 +: 8],
                            samples_3[(row_index*4+1)*32+16 +: 8],
                            samples_3[(row_index*4+2)*32+16 +: 8],
                            samples_3[(row_index*4+3)*32+16 +: 8],
                            $signed(wx_3[15:0]), $signed(wx_3[31:16]),
                            $signed(wx_3[47:32]), $signed(wx_3[63:48]));
                        horizontal_pairs_4[row_index*3+2] <= weighted_four_pairs(
                            samples_3[(row_index*4+0)*32+8 +: 8],
                            samples_3[(row_index*4+1)*32+8 +: 8],
                            samples_3[(row_index*4+2)*32+8 +: 8],
                            samples_3[(row_index*4+3)*32+8 +: 8],
                            $signed(wx_3[15:0]), $signed(wx_3[31:16]),
                            $signed(wx_3[47:32]), $signed(wx_3[63:48]));
                    end
                    wy_4 <= wy_3;
                    meta_4 <= meta_3;
                end
            end
            if (r5) begin
                v5 <= v4;
                if (v4) begin
                    for (channel_index = 0; channel_index < 12; channel_index = channel_index + 1)
                        horizontal_5[channel_index] <=
                            $signed(horizontal_pairs_4[channel_index][25:0]) +
                            $signed(horizontal_pairs_4[channel_index][51:26]);
                    wy_5 <= wy_4;
                    meta_5 <= meta_4;
                end
            end
            if (r6) begin
                v6 <= v5;
                if (v5) begin
                    for (channel_index = 0; channel_index < 3; channel_index = channel_index + 1)
                        for (row_index = 0; row_index < 4; row_index = row_index + 1)
                            vertical_product_6[channel_index*4+row_index] <=
                                horizontal_5[row_index*3+channel_index]
                                * $signed(wy_5[row_index*16 +: 16]);
                    meta_6 <= meta_5;
                end
            end
            if (r7) begin
                m_valid <= v6;
                if (v6) begin
                    m_geometry_valid <= meta_6[87] && (&meta_6[86:71]);
                    m_pixel <= (meta_6[87] && (&meta_6[86:71]))
                        ? {out_red, out_green, out_blue, 8'h00} : 32'd0;
                    m_pixel_id <= meta_6[70:51];
                    m_frame_id <= meta_6[50:19];
                    m_param_version <= meta_6[18:3];
                    m_sof <= meta_6[2]; m_eol <= meta_6[1]; m_eof <= meta_6[0];
                end
            end
        end
    end
endmodule

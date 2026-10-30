`timescale 1ns / 1ps

// Output pixel -> ideal current-view source pixel. Coefficients and the
// reciprocal table use the format specified in docs/plan/2026-10-24-stage8-angle-mapping.md.
// The 17-stage elastic pipeline separates coefficient products, reciprocal
// estimation, and coordinate products while preserving one-pixel-per-cycle
// throughput and metadata alignment under downstream stalls.
module homography_mapper #(
    parameter integer INPUT_Q16 = 0
) (
    input  wire                clk,
    input  wire                rstn,
    input  wire [287:0]        coefficients,
    input  wire                s_valid,
    output wire                s_ready,
    input  wire [10:0]         s_u,
    input  wire [9:0]          s_v,
    input  wire signed [31:0]  s_u_q16,
    input  wire signed [31:0]  s_v_q16,
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
    localparam signed [43:0] MIN_D = 44'sd536870912;
    localparam signed [43:0] MAX_D = 44'sd2147483648;
    localparam signed [43:0] MAX_N = 44'sd1073741824;
    localparam signed [43:0] ONE_Q30 = 44'sd1073741824;
    localparam integer META_WIDTH = 71;

    wire advance = rstn && (!m_valid || m_ready);
    assign s_ready = advance;

    reg signed [31:0] h00_reg, h01_reg, h02_reg;
    reg signed [31:0] h10_reg, h11_reg, h12_reg;
    reg signed [31:0] h20_reg, h21_reg, h22_reg;
    // INPUT_Q16 preserves the fractional 3:2 pixel-center coordinates from
    // the scale mapper. Products are shifted back to the coefficient's
    // original Q format before the homography range checks and reciprocal LUT.
    reg signed [43:0] u_ext_reg, v_ext_reg;
    reg [META_WIDTH-1:0] input_meta;
    reg input_valid;
    wire signed [63:0] nx_u_product = $signed(h00_reg) * u_ext_reg;
    wire signed [63:0] nx_v_product = $signed(h01_reg) * v_ext_reg;
    wire signed [63:0] ny_u_product = $signed(h10_reg) * u_ext_reg;
    wire signed [63:0] ny_v_product = $signed(h11_reg) * v_ext_reg;
    wire signed [63:0] d_u_product  = $signed(h20_reg) * u_ext_reg;
    wire signed [63:0] d_v_product  = $signed(h21_reg) * v_ext_reg;

    reg signed [43:0] nx_mul_u0, nx_mul_v0, nx_bias0;
    reg signed [43:0] ny_mul_u0, ny_mul_v0, ny_bias0;
    reg signed [43:0] d_mul_u0, d_mul_v0, d_bias0;
    reg signed [43:0] nx_pair1, nx_bias1, ny_pair1, ny_bias1;
    reg signed [43:0] d_pair1, d_bias1;
    reg signed [43:0] nx_sum2, ny_sum2, d_sum2;
    wire signed [43:0] nx_sum = nx_pair1 + nx_bias1;
    wire signed [43:0] ny_sum = ny_pair1 + ny_bias1;
    wire signed [43:0] d_sum = d_pair1 + d_bias1;
    wire input_in_range = d_sum2 >= MIN_D && d_sum2 < MAX_D &&
        nx_sum2 >= -MAX_N && nx_sum2 <= MAX_N &&
        ny_sum2 >= -MAX_N && ny_sum2 <= MAX_N;
    wire signed [43:0] d_for_rom = input_in_range ? d_sum2 : ONE_Q30;
    wire [9:0] address2 = (d_for_rom - MIN_D) >> 21;

    reg [31:0] seed_rom [0:1023];
    initial $readmemh("source/rtl/correction/reciprocal_seed_q30.mem", seed_rom);

    reg [16:0] valid_pipe;
    reg [META_WIDTH-1:0] meta [0:16];
    reg range3, range4, range5, range6, range7, range8;
    reg range9, range10, range11, range12, range13, range14, range15, range16;
    reg signed [43:0] nx3, ny3, d3;
    reg signed [43:0] nx4, ny4, nx5, ny5, nx6, ny6, nx7, ny7;
    reg signed [43:0] nx8, ny8, nx9, ny9, nx10, ny10, nx11, ny11;
    reg [31:0] seed3, seed4, seed5, seed6, seed7, seed8, seed9;
    reg [31:0] dr_p0_4, dr_p1_4, dr_p2_4, dr_p3_4;
    reg [31:0] dr_p0_5, dr_p3_5, dr_p3_6;
    reg [32:0] dr_cross5;
    reg [48:0] dr_low6;
    reg [63:0] dr_product7;
    reg [32:0] dr2, correction9;
    reg reciprocal_is_one3, reciprocal_is_one4, reciprocal_is_one5;
    reg reciprocal_is_one6, reciprocal_is_one7, reciprocal_is_one8;
    reg reciprocal_is_one9, reciprocal_is_one10;
    reg [65:0] newton_product10;
    reg [32:0] reciprocal11;
    reg [38:0] x_pll13, y_pll13;
    reg [37:0] x_plh13, y_plh13;
    reg signed [39:0] x_phl13, y_phl13;
    reg signed [38:0] x_phh13, y_phh13;
    reg signed [61:0] x_cross14, y_cross14;
    reg [38:0] x_pll14, y_pll14;
    reg signed [24:0] x_phh14, y_phh14;
    reg signed [24:0] x_phh15, y_phh15;
    reg signed [63:0] x_low15, y_low15;
    reg signed [63:0] product_x16, product_y16;
    reg signed [63:0] rounded_x16, rounded_y16;

    wire [32:0] dr_rounded = (dr_product7 + 64'd536870912) >> 30;
    wire [32:0] reciprocal_rounded =
        (newton_product10 + 66'd536870912) >> 30;
    function automatic signed [63:0] round_q30;
        input signed [63:0] product;
        reg [63:0] magnitude;
        begin
            magnitude = product < 0 ? -product : product;
            round_q30 = product < 0 ?
                -$signed((magnitude + 64'd536870912) >> 30) :
                 $signed((magnitude + 64'd536870912) >> 30);
        end
    endfunction

    wire output_in_range = rounded_x16 >= -64'sd2147483648 &&
        rounded_x16 <= 64'sd2147483647 &&
        rounded_y16 >= -64'sd2147483648 &&
        rounded_y16 <= 64'sd2147483647;

    always @(posedge clk) begin
        if (!rstn) begin
            valid_pipe <= 17'b0;
            input_valid <= 1'b0;
            m_valid <= 1'b0;
            m_sx <= 0; m_sy <= 0; m_geometry_valid <= 0;
            m_pixel_id <= 0; m_frame_id <= 0; m_param_version <= 0;
            m_sof <= 0; m_eol <= 0; m_eof <= 0;
        end else if (advance) begin
            m_valid <= valid_pipe[16];
            if (valid_pipe[16]) begin
                m_sx <= output_in_range ? rounded_x16[31:0] : 32'sd0;
                m_sy <= output_in_range ? rounded_y16[31:0] : 32'sd0;
                m_geometry_valid <= range16 && output_in_range;
                {m_pixel_id, m_frame_id, m_param_version, m_sof, m_eol, m_eof} <= meta[16];
            end

            valid_pipe <= {valid_pipe[15:0], input_valid};
            if (valid_pipe[15]) begin
                range16 <= range15;
                meta[16] <= meta[15];
                rounded_x16 <= round_q30(product_x16);
                rounded_y16 <= round_q30(product_y16);
            end
            if (valid_pipe[14]) begin
                range15 <= range14;
                meta[15] <= meta[14];
                product_x16 <= x_low15 + $signed({x_phh15, 39'b0});
                product_y16 <= y_low15 + $signed({y_phh15, 39'b0});
            end
            if (valid_pipe[13]) begin
                range14 <= range13;
                meta[14] <= meta[13];
                x_low15 <= $signed({{2{x_cross14[61]}}, x_cross14}) +
                    $signed({25'b0, x_pll14});
                y_low15 <= $signed({{2{y_cross14[61]}}, y_cross14}) +
                    $signed({25'b0, y_pll14});
                x_phh15 <= x_phh14;
                y_phh15 <= y_phh14;
            end
            if (valid_pipe[12]) begin
                range13 <= range12;
                meta[13] <= meta[12];
                x_cross14 <= ($signed({24'b0, x_plh13}) <<< 17) +
                    ($signed({{22{x_phl13[39]}}, x_phl13}) <<< 22);
                y_cross14 <= ($signed({24'b0, y_plh13}) <<< 17) +
                    ($signed({{22{y_phl13[39]}}, y_phl13}) <<< 22);
                x_pll14 <= x_pll13;
                y_pll14 <= y_pll13;
                x_phh14 <= x_phh13[24:0];
                y_phh14 <= y_phh13[24:0];
            end
            if (valid_pipe[11]) begin
                range12 <= range11;
                meta[12] <= meta[11];
                x_pll13 <= {17'b0, nx11[21:0]} * {22'b0, reciprocal11[16:0]};
                y_pll13 <= {17'b0, ny11[21:0]} * {22'b0, reciprocal11[16:0]};
                x_plh13 <= {16'b0, nx11[21:0]} * {22'b0, reciprocal11[32:17]};
                y_plh13 <= {16'b0, ny11[21:0]} * {22'b0, reciprocal11[32:17]};
                x_phl13 <= $signed({{18{nx11[43]}}, nx11[43:22]}) *
                    $signed({22'b0, 1'b0, reciprocal11[16:0]});
                y_phl13 <= $signed({{18{ny11[43]}}, ny11[43:22]}) *
                    $signed({22'b0, 1'b0, reciprocal11[16:0]});
                x_phh13 <= $signed({{17{nx11[43]}}, nx11[43:22]}) *
                    $signed({23'b0, reciprocal11[32:17]});
                y_phh13 <= $signed({{17{ny11[43]}}, ny11[43:22]}) *
                    $signed({23'b0, reciprocal11[32:17]});
            end
            if (valid_pipe[10]) begin
                range11 <= range10;
                meta[11] <= meta[10];
                nx11 <= nx10; ny11 <= ny10;
                reciprocal11 <= reciprocal_is_one10 ? 33'd1073741824 :
                    reciprocal_rounded;
            end
            if (valid_pipe[9]) begin
                range10 <= range9;
                meta[10] <= meta[9];
                nx10 <= nx9; ny10 <= ny9;
                reciprocal_is_one10 <= reciprocal_is_one9;
                newton_product10 <= $unsigned({1'b0, seed9}) *
                    $unsigned(correction9);
            end
            if (valid_pipe[8]) begin
                range9 <= range8;
                meta[9] <= meta[8];
                nx9 <= nx8; ny9 <= ny8;
                seed9 <= seed8;
                reciprocal_is_one9 <= reciprocal_is_one8;
                correction9 <= 33'h080000000 - dr2;
            end
            if (valid_pipe[7]) begin
                range8 <= range7;
                meta[8] <= meta[7];
                nx8 <= nx7; ny8 <= ny7;
                seed8 <= seed7;
                reciprocal_is_one8 <= reciprocal_is_one7;
                dr2 <= dr_rounded;
            end
            if (valid_pipe[6]) begin
                range7 <= range6;
                meta[7] <= meta[6];
                nx7 <= nx6; ny7 <= ny6;
                seed7 <= seed6;
                reciprocal_is_one7 <= reciprocal_is_one6;
                dr_product7 <= {dr_p3_6, 32'b0} + {15'b0, dr_low6};
            end
            if (valid_pipe[5]) begin
                range6 <= range5;
                meta[6] <= meta[5];
                nx6 <= nx5; ny6 <= ny5;
                seed6 <= seed5;
                reciprocal_is_one6 <= reciprocal_is_one5;
                dr_low6 <= {dr_cross5, 16'b0} + {17'b0, dr_p0_5};
                dr_p3_6 <= dr_p3_5;
            end
            if (valid_pipe[4]) begin
                range5 <= range4;
                meta[5] <= meta[4];
                nx5 <= nx4; ny5 <= ny4;
                seed5 <= seed4;
                reciprocal_is_one5 <= reciprocal_is_one4;
                dr_cross5 <= {1'b0, dr_p1_4} + {1'b0, dr_p2_4};
                dr_p0_5 <= dr_p0_4;
                dr_p3_5 <= dr_p3_4;
            end
            if (valid_pipe[3]) begin
                range4 <= range3;
                meta[4] <= meta[3];
                nx4 <= nx3; ny4 <= ny3;
                seed4 <= seed3;
                reciprocal_is_one4 <= reciprocal_is_one3;
                dr_p0_4 <= {16'b0, d3[15:0]} * {16'b0, seed3[15:0]};
                dr_p1_4 <= {16'b0, d3[15:0]} * {16'b0, seed3[31:16]};
                dr_p2_4 <= {16'b0, d3[31:16]} * {16'b0, seed3[15:0]};
                dr_p3_4 <= {16'b0, d3[31:16]} * {16'b0, seed3[31:16]};
            end
            if (valid_pipe[2]) begin
                range3 <= input_in_range;
                meta[3] <= meta[2];
                nx3 <= input_in_range ? nx_sum2 : 44'sd0;
                ny3 <= input_in_range ? ny_sum2 : 44'sd0;
                d3 <= input_in_range ? d_sum2 : ONE_Q30;
                seed3 <= seed_rom[address2];
                reciprocal_is_one3 <= !input_in_range || (d_sum2 == ONE_Q30);
            end
            if (valid_pipe[1]) begin
                meta[2] <= meta[1];
                nx_sum2 <= nx_sum;
                ny_sum2 <= ny_sum;
                d_sum2 <= d_sum;
            end
            if (valid_pipe[0]) begin
                meta[1] <= meta[0];
                nx_pair1 <= nx_mul_u0 + nx_mul_v0;
                nx_bias1 <= nx_bias0;
                ny_pair1 <= ny_mul_u0 + ny_mul_v0;
                ny_bias1 <= ny_bias0;
                d_pair1 <= d_mul_u0 + d_mul_v0;
                d_bias1 <= d_bias0;
            end
            input_valid <= s_valid;
            if (s_valid) begin
                h00_reg <= coefficients[31:0]; h01_reg <= coefficients[63:32];
                h02_reg <= coefficients[95:64];
                h10_reg <= coefficients[127:96]; h11_reg <= coefficients[159:128];
                h12_reg <= coefficients[191:160];
                h20_reg <= coefficients[223:192]; h21_reg <= coefficients[255:224];
                h22_reg <= coefficients[287:256];
                u_ext_reg <= INPUT_Q16 ? $signed({{12{s_u_q16[31]}}, s_u_q16}) :
                                          ($signed({1'b0, s_u}) <<< 16);
                v_ext_reg <= INPUT_Q16 ? $signed({{12{s_v_q16[31]}}, s_v_q16}) :
                                          ($signed({1'b0, s_v}) <<< 16);
                input_meta <= {s_pixel_id, s_frame_id, s_param_version, s_sof, s_eol, s_eof};
            end
            if (input_valid) begin
                meta[0] <= input_meta;
                nx_mul_u0 <= nx_u_product >>> 16; nx_mul_v0 <= nx_v_product >>> 16; nx_bias0 <= h02_reg;
                ny_mul_u0 <= ny_u_product >>> 16; ny_mul_v0 <= ny_v_product >>> 16; ny_bias0 <= h12_reg;
                d_mul_u0 <= d_u_product >>> 16; d_mul_v0 <= d_v_product >>> 16; d_bias0 <= h22_reg;
            end
        end
    end
endmodule

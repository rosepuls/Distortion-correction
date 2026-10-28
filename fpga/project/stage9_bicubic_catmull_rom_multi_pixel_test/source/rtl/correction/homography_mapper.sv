`timescale 1ns / 1ps

// Output pixel -> ideal current-view source pixel. Coefficients and the
// reciprocal table use the format specified in docs/plan/2026-10-24-stage8-angle-mapping.md.
// All stages advance together, so metadata and coordinates remain aligned
// during downstream stalls. One coordinate can enter on every free clock.
module homography_mapper (
    input  wire                clk,
    input  wire                rstn,
    input  wire [287:0]        coefficients,
    input  wire                s_valid,
    output wire                s_ready,
    input  wire [10:0]         s_u,
    input  wire [9:0]          s_v,
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
    localparam [31:0] TWO_Q30 = 32'h80000000;
    localparam integer META_WIDTH = 71;

    wire advance = rstn && (!m_valid || m_ready);
    assign s_ready = advance;

    wire signed [31:0] h00 = coefficients[31:0];
    wire signed [31:0] h01 = coefficients[63:32];
    wire signed [31:0] h02 = coefficients[95:64];
    wire signed [31:0] h10 = coefficients[127:96];
    wire signed [31:0] h11 = coefficients[159:128];
    wire signed [31:0] h12 = coefficients[191:160];
    wire signed [31:0] h20 = coefficients[223:192];
    wire signed [31:0] h21 = coefficients[255:224];
    wire signed [31:0] h22 = coefficients[287:256];

    wire signed [43:0] u_ext = $signed({1'b0, s_u});
    wire signed [43:0] v_ext = $signed({1'b0, s_v});
    wire signed [43:0] nx_in = h00 * u_ext + h01 * v_ext + h02;
    wire signed [43:0] ny_in = h10 * u_ext + h11 * v_ext + h12;
    wire signed [43:0] d_in  = h20 * u_ext + h21 * v_ext + h22;
    wire input_in_range = d_in >= MIN_D && d_in < MAX_D &&
        nx_in >= -MAX_N && nx_in <= MAX_N &&
        ny_in >= -MAX_N && ny_in <= MAX_N;

    reg [31:0] seed_rom [0:1023];
    initial $readmemh("source/rtl/correction/reciprocal_seed_q30.mem", seed_rom);

    reg [4:0] valid_pipe;
    reg [META_WIDTH-1:0] meta [0:4];
    reg range0, range1, range2, range3, range4;
    reg signed [43:0] nx0, ny0, d0;
    reg signed [43:0] nx1, ny1, d1;
    reg signed [43:0] nx2, ny2, d2;
    reg signed [43:0] nx3, ny3;
    reg [31:0] seed1, seed2;
    reg [32:0] dr2;
    reg [32:0] reciprocal3;
    reg signed [63:0] product_x4, product_y4;

    wire [9:0] address0 = (d0 - MIN_D) >> 21;
    wire [63:0] dr_product = $unsigned(d1[31:0]) * $unsigned(seed1);
    wire [32:0] dr_rounded = (dr_product + 64'd536870912) >> 30;
    wire [32:0] correction = 33'h080000000 - dr2;
    wire [65:0] newton_product = $unsigned({1'b0, seed2}) * $unsigned(correction);
    wire [32:0] reciprocal_next = d2 == ONE_Q30 ? 33'd1073741824 :
        (newton_product + 66'd536870912) >> 30;
    wire signed [63:0] x_product = $signed(nx3) * $signed(reciprocal3);
    wire signed [63:0] y_product = $signed(ny3) * $signed(reciprocal3);

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

    wire signed [63:0] rounded_x = round_q30(product_x4);
    wire signed [63:0] rounded_y = round_q30(product_y4);
    wire output_in_range = rounded_x >= -64'sd2147483648 &&
        rounded_x <= 64'sd2147483647 &&
        rounded_y >= -64'sd2147483648 &&
        rounded_y <= 64'sd2147483647;

    always @(posedge clk) begin
        if (!rstn) begin
            valid_pipe <= 5'b0;
            m_valid <= 1'b0;
            m_sx <= 0; m_sy <= 0; m_geometry_valid <= 0;
            m_pixel_id <= 0; m_frame_id <= 0; m_param_version <= 0;
            m_sof <= 0; m_eol <= 0; m_eof <= 0;
        end else if (advance) begin
            m_valid <= valid_pipe[4];
            if (valid_pipe[4]) begin
                m_sx <= output_in_range ? rounded_x[31:0] : 32'sd0;
                m_sy <= output_in_range ? rounded_y[31:0] : 32'sd0;
                m_geometry_valid <= range4 && output_in_range;
                {m_pixel_id, m_frame_id, m_param_version, m_sof, m_eol, m_eof} <= meta[4];
            end

            valid_pipe <= {valid_pipe[3:0], s_valid};
            if (valid_pipe[3]) begin
                range4 <= range3;
                meta[4] <= meta[3];
                product_x4 <= x_product;
                product_y4 <= y_product;
            end
            if (valid_pipe[2]) begin
                range3 <= range2;
                meta[3] <= meta[2];
                nx3 <= nx2; ny3 <= ny2;
                reciprocal3 <= reciprocal_next;
            end
            if (valid_pipe[1]) begin
                range2 <= range1;
                meta[2] <= meta[1];
                nx2 <= nx1; ny2 <= ny1; d2 <= d1;
                seed2 <= seed1;
                dr2 <= dr_rounded;
            end
            if (valid_pipe[0]) begin
                range1 <= range0;
                meta[1] <= meta[0];
                nx1 <= nx0; ny1 <= ny0; d1 <= d0;
                seed1 <= seed_rom[address0];
            end
            if (s_valid) begin
                range0 <= input_in_range;
                meta[0] <= {s_pixel_id, s_frame_id, s_param_version, s_sof, s_eol, s_eof};
                nx0 <= input_in_range ? nx_in : 44'sd0;
                ny0 <= input_in_range ? ny_in : 44'sd0;
                d0 <= input_in_range ? d_in : ONE_Q30;
            end
        end
    end
endmodule

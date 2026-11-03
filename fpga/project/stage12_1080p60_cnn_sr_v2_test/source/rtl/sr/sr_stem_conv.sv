`timescale 1ns / 1ps
`include "source/rtl/sr/weights/sr_stem_rom_cases.vh"

// Trained 1->8 stem convolution, one input pixel per cycle. The nine products
// per channel are computed in parallel, then reduced through registered pair,
// group, bias, requant and clamp stages. Only valid bits reset.
module sr_stem_conv #(
    parameter integer CHANNELS = 8,
    parameter integer PIXEL_ID_WIDTH = 21,
    parameter integer FRAME_ID_WIDTH = 32
) (
    input  wire                      clk,
    input  wire                      rstn,
    input  wire                      s_valid,
    output wire                      s_ready,
    input  wire [71:0]               s_window,
    input  wire [10:0]               s_x,
    input  wire [9:0]                s_y,
    input  wire [PIXEL_ID_WIDTH-1:0] s_pixel_id,
    input  wire [FRAME_ID_WIDTH-1:0] s_frame_id,
    input  wire                      s_sof,
    input  wire                      s_eol,
    input  wire                      s_eof,
    output wire                      m_valid,
    input  wire                      m_ready,
    output wire [CHANNELS*8-1:0]     m_features,
    output wire [10:0]               m_x,
    output wire [9:0]                m_y,
    output wire [PIXEL_ID_WIDTH-1:0] m_pixel_id,
    output wire [FRAME_ID_WIDTH-1:0] m_frame_id,
    output wire                      m_sof,
    output wire                      m_eol,
    output wire                      m_eof
);
    localparam integer PIPE_STAGES = 11;
    function signed [7:0] stem_weight_at;
        input integer address;
        reg [7:0] rom_value;
        begin
            rom_value = 0;
            case (address)
                `SR_STEM_WEIGHT_CASES
                default: rom_value = 0;
            endcase
            stem_weight_at = rom_value;
        end
    endfunction
    function signed [31:0] stem_bias_at;
        input integer address;
        reg [31:0] rom_value;
        begin
            rom_value = 0;
            case (address)
                `SR_STEM_BIAS_CASES
                default: rom_value = 0;
            endcase
            stem_bias_at = rom_value;
        end
    endfunction
    function signed [31:0] stem_requant_mult_at;
        input integer address;
        reg [31:0] rom_value;
        begin
            rom_value = 0;
            case (address)
                `SR_STEM_REQUANT_MULT_CASES
                default: rom_value = 0;
            endcase
            stem_requant_mult_at = rom_value;
        end
    endfunction
    function [7:0] stem_requant_shift_at;
        input integer address;
        reg [7:0] rom_value;
        begin
            rom_value = 0;
            case (address)
                `SR_STEM_REQUANT_SHIFT_CASES
                default: rom_value = 0;
            endcase
            stem_requant_shift_at = rom_value;
        end
    endfunction

    reg [PIPE_STAGES-1:0] valid_pipe;
    wire [PIPE_STAGES-1:0] ready_pipe;
    assign ready_pipe[PIPE_STAGES-1] = !valid_pipe[PIPE_STAGES-1] || m_ready;
    genvar ri;
    generate
        for (ri = 0; ri < PIPE_STAGES-1; ri = ri + 1) begin: g_ready
            assign ready_pipe[ri] = !valid_pipe[ri] || ready_pipe[ri+1];
        end
    endgenerate
    assign s_ready = rstn && ready_pipe[0];
    assign m_valid = rstn && valid_pipe[PIPE_STAGES-1];

    reg [71:0] window0;
    reg [10:0] x_pipe [0:PIPE_STAGES-1];
    reg [9:0] y_pipe [0:PIPE_STAGES-1];
    reg [PIXEL_ID_WIDTH-1:0] id_pipe [0:PIPE_STAGES-1];
    reg [FRAME_ID_WIDTH-1:0] frame_pipe [0:PIPE_STAGES-1];
    reg sof_pipe [0:PIPE_STAGES-1];
    reg eol_pipe [0:PIPE_STAGES-1];
    reg eof_pipe [0:PIPE_STAGES-1];

    reg signed [15:0] products1 [0:CHANNELS*9-1];
    reg signed [16:0] pairs2 [0:CHANNELS*5-1];
    reg signed [17:0] groups3 [0:CHANNELS*3-1];
    reg signed [18:0] middle4 [0:CHANNELS-1];
    reg signed [17:0] tail4 [0:CHANNELS-1];
    reg signed [18:0] middle5 [0:CHANNELS-1];
    reg signed [31:0] tail_bias5 [0:CHANNELS-1];
    reg signed [31:0] accum6 [0:CHANNELS-1];
    reg signed [63:0] requant_product7 [0:CHANNELS-1];
    reg [63:0] abs_product8 [0:CHANNELS-1];
    reg product_sign8 [0:CHANNELS-1];
    reg [63:0] shifted_magnitude9 [0:CHANNELS-1];
    reg rounding_bit9 [0:CHANNELS-1];
    reg product_sign9 [0:CHANNELS-1];
    reg [CHANNELS*8-1:0] features10;

    reg signed [15:0] product_comb [0:CHANNELS*9-1];
    integer ch, tap, st;
    always @* begin
        for (ch = 0; ch < CHANNELS; ch = ch + 1) begin
            for (tap = 0; tap < 9; tap = tap + 1)
                product_comb[ch*9+tap] =
                    $signed({1'b0, window0[8*(8-tap) +: 8]}) *
                    stem_weight_at(ch*9+tap);
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) valid_pipe <= {PIPE_STAGES{1'b0}};
        else begin
            if (ready_pipe[0]) valid_pipe[0] <= s_valid;
            for (st = 1; st < PIPE_STAGES; st = st + 1)
                if (ready_pipe[st]) valid_pipe[st] <= valid_pipe[st-1];
        end
    end

    always @(posedge clk) begin
        if (rstn && ready_pipe[0] && s_valid) begin
            window0 <= s_window;
            x_pipe[0] <= s_x;
            y_pipe[0] <= s_y;
            id_pipe[0] <= s_pixel_id;
            frame_pipe[0] <= s_frame_id;
            sof_pipe[0] <= s_sof;
            eol_pipe[0] <= s_eol;
            eof_pipe[0] <= s_eof;
        end
        for (st = 1; st < PIPE_STAGES; st = st + 1) begin
            if (rstn && ready_pipe[st]) begin
                x_pipe[st] <= x_pipe[st-1];
                y_pipe[st] <= y_pipe[st-1];
                id_pipe[st] <= id_pipe[st-1];
                frame_pipe[st] <= frame_pipe[st-1];
                sof_pipe[st] <= sof_pipe[st-1];
                eol_pipe[st] <= eol_pipe[st-1];
                eof_pipe[st] <= eof_pipe[st-1];
            end
        end

        if (rstn && ready_pipe[1] && valid_pipe[0])
            for (ch = 0; ch < CHANNELS*9; ch = ch + 1)
                products1[ch] <= product_comb[ch];

        if (rstn && ready_pipe[2] && valid_pipe[1]) begin
            for (ch = 0; ch < CHANNELS; ch = ch + 1) begin
                pairs2[ch*5+0] <= {products1[ch*9+0][15], products1[ch*9+0]} +
                                  {products1[ch*9+1][15], products1[ch*9+1]};
                pairs2[ch*5+1] <= {products1[ch*9+2][15], products1[ch*9+2]} +
                                  {products1[ch*9+3][15], products1[ch*9+3]};
                pairs2[ch*5+2] <= {products1[ch*9+4][15], products1[ch*9+4]} +
                                  {products1[ch*9+5][15], products1[ch*9+5]};
                pairs2[ch*5+3] <= {products1[ch*9+6][15], products1[ch*9+6]} +
                                  {products1[ch*9+7][15], products1[ch*9+7]};
                pairs2[ch*5+4] <= {products1[ch*9+8][15], products1[ch*9+8]};
            end
        end

        if (rstn && ready_pipe[3] && valid_pipe[2]) begin
            for (ch = 0; ch < CHANNELS; ch = ch + 1) begin
                groups3[ch*3+0] <= {pairs2[ch*5+0][16], pairs2[ch*5+0]} +
                                   {pairs2[ch*5+1][16], pairs2[ch*5+1]};
                groups3[ch*3+1] <= {pairs2[ch*5+2][16], pairs2[ch*5+2]} +
                                   {pairs2[ch*5+3][16], pairs2[ch*5+3]};
                groups3[ch*3+2] <= {pairs2[ch*5+4][16], pairs2[ch*5+4]};
            end
        end

        if (rstn && ready_pipe[4] && valid_pipe[3]) begin
            for (ch = 0; ch < CHANNELS; ch = ch + 1) begin
                middle4[ch] <= {groups3[ch*3+0][17], groups3[ch*3+0]} +
                               {groups3[ch*3+1][17], groups3[ch*3+1]};
                tail4[ch] <= groups3[ch*3+2];
            end
        end

        if (rstn && ready_pipe[5] && valid_pipe[4]) begin
            for (ch = 0; ch < CHANNELS; ch = ch + 1) begin
                middle5[ch] <= middle4[ch];
                tail_bias5[ch] <= stem_bias_at(ch) + tail4[ch];
            end
        end

        if (rstn && ready_pipe[6] && valid_pipe[5])
            for (ch = 0; ch < CHANNELS; ch = ch + 1)
                accum6[ch] <= {{13{middle5[ch][18]}}, middle5[ch]} + tail_bias5[ch];

        if (rstn && ready_pipe[7] && valid_pipe[6])
            for (ch = 0; ch < CHANNELS; ch = ch + 1)
                requant_product7[ch] <= accum6[ch] * stem_requant_mult_at(ch);

        if (rstn && ready_pipe[8] && valid_pipe[7]) begin
            for (ch = 0; ch < CHANNELS; ch = ch + 1) begin: g_requant
                abs_product8[ch] <= requant_product7[ch][63] ?
                                    -requant_product7[ch] : requant_product7[ch];
                product_sign8[ch] <= requant_product7[ch][63];
            end
        end

        if (rstn && ready_pipe[9] && valid_pipe[8]) begin
            for (ch = 0; ch < CHANNELS; ch = ch + 1) begin: g_shift
                product_sign9[ch] <= product_sign8[ch];
                if (stem_requant_shift_at(ch) == 0) begin
                    shifted_magnitude9[ch] <= abs_product8[ch];
                    rounding_bit9[ch] <= 1'b0;
                end else begin
                    shifted_magnitude9[ch] <= abs_product8[ch] >> stem_requant_shift_at(ch);
                    rounding_bit9[ch] <= abs_product8[ch][stem_requant_shift_at(ch)-1'b1];
                end
            end
        end

        if (rstn && ready_pipe[10] && valid_pipe[9]) begin
            for (ch = 0; ch < CHANNELS; ch = ch + 1) begin: g_clamp
                reg [8:0] rounded_low;
                rounded_low = {1'b0, shifted_magnitude9[ch][7:0]} + rounding_bit9[ch];
                if (product_sign9[ch]) features10[ch*8 +: 8] <= 8'd0;
                else if (|shifted_magnitude9[ch][63:8] || rounded_low[8])
                    features10[ch*8 +: 8] <= 8'd255;
                else features10[ch*8 +: 8] <= rounded_low[7:0];
            end
        end
    end

    assign m_features = features10;
    assign m_x = x_pipe[PIPE_STAGES-1];
    assign m_y = y_pipe[PIPE_STAGES-1];
    assign m_pixel_id = id_pipe[PIPE_STAGES-1];
    assign m_frame_id = frame_pipe[PIPE_STAGES-1];
    assign m_sof = sof_pipe[PIPE_STAGES-1];
    assign m_eol = eol_pipe[PIPE_STAGES-1];
    assign m_eof = eof_pipe[PIPE_STAGES-1];
endmodule

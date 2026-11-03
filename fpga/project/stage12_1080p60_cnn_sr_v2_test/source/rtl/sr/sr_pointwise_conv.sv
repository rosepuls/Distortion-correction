`timescale 1ns / 1ps
`include "source/rtl/sr/weights/sr_block1_pointwise_rom_cases.vh"

// Trained 8x8 block1 1x1 convolution. The reduction, bias, requantization,
// rounding and clamp are separated by registers to keep the 125 MHz path short.
module sr_pointwise_conv #(
    parameter integer CHANNELS = 8,
    parameter integer PIXEL_ID_WIDTH = 21,
    parameter integer FRAME_ID_WIDTH = 32
) (
    input wire clk, input wire rstn,
    input wire s_valid, output wire s_ready,
    input wire [CHANNELS*8-1:0] s_features,
    input wire [CHANNELS*8-1:0] s_skip,
    input wire [10:0] s_x, input wire [9:0] s_y,
    input wire [PIXEL_ID_WIDTH-1:0] s_pixel_id,
    input wire [FRAME_ID_WIDTH-1:0] s_frame_id,
    input wire s_sof, input wire s_eol, input wire s_eof,
    output wire m_valid, input wire m_ready,
    output wire [CHANNELS*8-1:0] m_features,
    output wire [CHANNELS*8-1:0] m_skip,
    output wire [10:0] m_x, output wire [9:0] m_y,
    output wire [PIXEL_ID_WIDTH-1:0] m_pixel_id,
    output wire [FRAME_ID_WIDTH-1:0] m_frame_id,
    output wire m_sof, output wire m_eol, output wire m_eof
);
    localparam integer PIPE_STAGES = 11;
    function signed [7:0] block1_pw_weight_at;
        input integer address;
        reg [7:0] rom_value;
        begin
            rom_value = 0;
            case (address)
                `SR_BLOCK1_PW_WEIGHT_CASES
                default: rom_value = 0;
            endcase
            block1_pw_weight_at = rom_value;
        end
    endfunction
    function signed [31:0] block1_pw_bias_at;
        input integer address;
        reg [31:0] rom_value;
        begin
            rom_value = 0;
            case (address)
                `SR_BLOCK1_PW_BIAS_CASES
                default: rom_value = 0;
            endcase
            block1_pw_bias_at = rom_value;
        end
    endfunction
    function signed [31:0] block1_pw_requant_mult_at;
        input integer address;
        reg [31:0] rom_value;
        begin
            rom_value = 0;
            case (address)
                `SR_BLOCK1_PW_REQUANT_MULT_CASES
                default: rom_value = 0;
            endcase
            block1_pw_requant_mult_at = rom_value;
        end
    endfunction
    function [7:0] block1_pw_requant_shift_at;
        input integer address;
        reg [7:0] rom_value;
        begin
            rom_value = 0;
            case (address)
                `SR_BLOCK1_PW_REQUANT_SHIFT_CASES
                default: rom_value = 0;
            endcase
            block1_pw_requant_shift_at = rom_value;
        end
    endfunction
    reg [PIPE_STAGES-1:0] valid_pipe;
    wire [PIPE_STAGES-1:0] ready_pipe;
    assign ready_pipe[PIPE_STAGES-1] = !valid_pipe[PIPE_STAGES-1] || m_ready;
    genvar ri;
    generate for (ri=0; ri<PIPE_STAGES-1; ri=ri+1) begin: g_ready
        assign ready_pipe[ri] = !valid_pipe[ri] || ready_pipe[ri+1];
    end endgenerate
    assign s_ready = rstn && ready_pipe[0];
    assign m_valid = rstn && valid_pipe[PIPE_STAGES-1];

    reg [CHANNELS*8-1:0] input0;
    reg [10:0] x_pipe [0:PIPE_STAGES-1];
    reg [9:0] y_pipe [0:PIPE_STAGES-1];
    reg [CHANNELS*8-1:0] skip_pipe [0:PIPE_STAGES-1];
    reg [PIXEL_ID_WIDTH-1:0] id_pipe [0:PIPE_STAGES-1];
    reg [FRAME_ID_WIDTH-1:0] frame_pipe [0:PIPE_STAGES-1];
    reg sof_pipe [0:PIPE_STAGES-1], eol_pipe [0:PIPE_STAGES-1], eof_pipe [0:PIPE_STAGES-1];
    reg signed [15:0] products1 [0:CHANNELS*CHANNELS-1];
    reg signed [16:0] pairs2 [0:CHANNELS*4-1];
    reg signed [17:0] groups3 [0:CHANNELS*2-1];
    reg signed [18:0] sums4 [0:CHANNELS-1];
    reg signed [31:0] accum5 [0:CHANNELS-1];
    reg signed [63:0] requant_product6 [0:CHANNELS-1];
    reg [63:0] abs_product7 [0:CHANNELS-1], shifted_magnitude8 [0:CHANNELS-1];
    reg [63:0] shifted_magnitude9 [0:CHANNELS-1];
    reg product_sign7 [0:CHANNELS-1], product_sign8 [0:CHANNELS-1], product_sign9 [0:CHANNELS-1];
    reg rounding_bit8 [0:CHANNELS-1], rounding_bit9 [0:CHANNELS-1];
    reg [CHANNELS*8-1:0] features10;
    reg signed [15:0] product_comb [0:CHANNELS*CHANNELS-1];
    integer ch, ic, st;
    always @* begin
        for (ch=0; ch<CHANNELS; ch=ch+1)
            for (ic=0; ic<CHANNELS; ic=ic+1)
                product_comb[ch*CHANNELS+ic] =
                    $signed({1'b0,input0[ic*8 +: 8]}) * block1_pw_weight_at(ch*CHANNELS+ic);
    end
    always @(posedge clk or negedge rstn) begin
        if (!rstn) valid_pipe <= {PIPE_STAGES{1'b0}};
        else begin
            if (ready_pipe[0]) valid_pipe[0] <= s_valid;
            for (st=1; st<PIPE_STAGES; st=st+1)
                if (ready_pipe[st]) valid_pipe[st] <= valid_pipe[st-1];
        end
    end
    always @(posedge clk) begin
        if (rstn && ready_pipe[0] && s_valid) begin
            input0 <= s_features; skip_pipe[0]<=s_skip; x_pipe[0]<=s_x; y_pipe[0]<=s_y; id_pipe[0]<=s_pixel_id;
            frame_pipe[0]<=s_frame_id; sof_pipe[0]<=s_sof; eol_pipe[0]<=s_eol; eof_pipe[0]<=s_eof;
        end
        for (st=1; st<PIPE_STAGES; st=st+1) if (rstn && ready_pipe[st]) begin
            x_pipe[st]<=x_pipe[st-1]; y_pipe[st]<=y_pipe[st-1]; skip_pipe[st]<=skip_pipe[st-1]; id_pipe[st]<=id_pipe[st-1];
            frame_pipe[st]<=frame_pipe[st-1]; sof_pipe[st]<=sof_pipe[st-1];
            eol_pipe[st]<=eol_pipe[st-1]; eof_pipe[st]<=eof_pipe[st-1];
        end
        if (rstn && ready_pipe[1] && valid_pipe[0])
            for (ch=0; ch<CHANNELS*CHANNELS; ch=ch+1) products1[ch]<=product_comb[ch];
        if (rstn && ready_pipe[2] && valid_pipe[1])
            for (ch=0; ch<CHANNELS; ch=ch+1) begin
                pairs2[ch*4]<= {products1[ch*8][15],products1[ch*8]} + {products1[ch*8+1][15],products1[ch*8+1]};
                pairs2[ch*4+1]<= {products1[ch*8+2][15],products1[ch*8+2]} + {products1[ch*8+3][15],products1[ch*8+3]};
                pairs2[ch*4+2]<= {products1[ch*8+4][15],products1[ch*8+4]} + {products1[ch*8+5][15],products1[ch*8+5]};
                pairs2[ch*4+3]<= {products1[ch*8+6][15],products1[ch*8+6]} + {products1[ch*8+7][15],products1[ch*8+7]};
            end
        if (rstn && ready_pipe[3] && valid_pipe[2])
            for (ch=0; ch<CHANNELS; ch=ch+1) begin
                groups3[ch*2]<= {pairs2[ch*4][16],pairs2[ch*4]} + {pairs2[ch*4+1][16],pairs2[ch*4+1]};
                groups3[ch*2+1]<= {pairs2[ch*4+2][16],pairs2[ch*4+2]} + {pairs2[ch*4+3][16],pairs2[ch*4+3]};
            end
        if (rstn && ready_pipe[4] && valid_pipe[3])
            for (ch=0; ch<CHANNELS; ch=ch+1)
                sums4[ch] <= {groups3[ch*2][17],groups3[ch*2]} + {groups3[ch*2+1][17],groups3[ch*2+1]};
        if (rstn && ready_pipe[5] && valid_pipe[4])
            for (ch=0; ch<CHANNELS; ch=ch+1)
                accum5[ch] <= {{13{sums4[ch][18]}},sums4[ch]} + block1_pw_bias_at(ch);
        if (rstn && ready_pipe[6] && valid_pipe[5])
            for (ch=0; ch<CHANNELS; ch=ch+1) requant_product6[ch] <= accum5[ch] * block1_pw_requant_mult_at(ch);
        if (rstn && ready_pipe[7] && valid_pipe[6])
            for (ch=0; ch<CHANNELS; ch=ch+1) begin
                abs_product7[ch] <= requant_product6[ch][63] ? -requant_product6[ch] : requant_product6[ch];
                product_sign7[ch] <= requant_product6[ch][63];
            end
        if (rstn && ready_pipe[8] && valid_pipe[7])
            for (ch=0; ch<CHANNELS; ch=ch+1) begin
                if (block1_pw_requant_shift_at(ch)==0) begin shifted_magnitude8[ch]<=abs_product7[ch]; rounding_bit8[ch]<=0; end
                else begin shifted_magnitude8[ch]<=abs_product7[ch]>>block1_pw_requant_shift_at(ch); rounding_bit8[ch]<=abs_product7[ch][block1_pw_requant_shift_at(ch)-1'b1]; end
                product_sign8[ch]<=product_sign7[ch];
            end
        if (rstn && ready_pipe[9] && valid_pipe[8])
            for (ch=0; ch<CHANNELS; ch=ch+1) begin
                shifted_magnitude9[ch]<=shifted_magnitude8[ch]; rounding_bit9[ch]<=rounding_bit8[ch];
                product_sign9[ch]<=product_sign8[ch];
            end
        if (rstn && ready_pipe[10] && valid_pipe[9])
            for (ch=0; ch<CHANNELS; ch=ch+1) begin: g_clamp
                reg [8:0] rounded_low;
                rounded_low={1'b0,shifted_magnitude9[ch][7:0]}+rounding_bit9[ch];
                if(product_sign9[ch]) features10[ch*8 +: 8]<=0;
                else if(|shifted_magnitude9[ch][63:8] || rounded_low[8]) features10[ch*8 +: 8]<=255;
                else features10[ch*8 +: 8]<=rounded_low[7:0];
            end
    end
    assign m_features=features10; assign m_skip=skip_pipe[PIPE_STAGES-1];
    assign m_x=x_pipe[PIPE_STAGES-1]; assign m_y=y_pipe[PIPE_STAGES-1];
    assign m_pixel_id=id_pipe[PIPE_STAGES-1]; assign m_frame_id=frame_pipe[PIPE_STAGES-1];
    assign m_sof=sof_pipe[PIPE_STAGES-1]; assign m_eol=eol_pipe[PIPE_STAGES-1]; assign m_eof=eof_pipe[PIPE_STAGES-1];
endmodule

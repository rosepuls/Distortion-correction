`timescale 1ns / 1ps
`include "source/rtl/sr/weights/sr_join_rom_cases.vh"

// Block residual join: independently requantize unsigned skip and branch
// activations, add, then saturate to uint8. The constant multiplies and the
// rounding/shift/add work are explicitly registered across short stages.
module sr_residual_join #(
    parameter integer BLOCK_INDEX = 0,
    parameter integer CHANNELS = 8,
    parameter integer PIXEL_ID_WIDTH = 21,
    parameter integer FRAME_ID_WIDTH = 32
) (
    input wire clk, input wire rstn,
    input wire s_valid, output wire s_ready,
    input wire [CHANNELS*8-1:0] s_skip,
    input wire [CHANNELS*8-1:0] s_branch,
    input wire [10:0] s_x, input wire [9:0] s_y,
    input wire [PIXEL_ID_WIDTH-1:0] s_pixel_id,
    input wire [FRAME_ID_WIDTH-1:0] s_frame_id,
    input wire s_sof, input wire s_eol, input wire s_eof,
    output wire m_valid, input wire m_ready,
    output wire [CHANNELS*8-1:0] m_features,
    output wire [10:0] m_x, output wire [9:0] m_y,
    output wire [PIXEL_ID_WIDTH-1:0] m_pixel_id,
    output wire [FRAME_ID_WIDTH-1:0] m_frame_id,
    output wire m_sof, output wire m_eol, output wire m_eof
);
    localparam integer PIPE_STAGES=5;
    function [31:0] join_constant_at;
        input integer address;
        reg [31:0] rom_value;
        begin
            rom_value = 0;
            case (address)
                `SR_BLOCK1_JOIN_CASES
                `SR_BLOCK2_JOIN_CASES
                default: rom_value = 0;
            endcase
            join_constant_at = rom_value;
        end
    endfunction
    wire [31:0] skip_mult=join_constant_at(BLOCK_INDEX*4);
    wire [31:0] branch_mult=join_constant_at(BLOCK_INDEX*4+2);
    wire [7:0] skip_shift=join_constant_at(BLOCK_INDEX*4+1);
    wire [7:0] branch_shift=join_constant_at(BLOCK_INDEX*4+3);
    reg [PIPE_STAGES-1:0] valid_pipe;
    wire [PIPE_STAGES-1:0] ready_pipe;
    assign ready_pipe[PIPE_STAGES-1]=!valid_pipe[PIPE_STAGES-1]||m_ready;
    genvar ri;
    generate for(ri=0;ri<PIPE_STAGES-1;ri=ri+1) begin:g_ready
        assign ready_pipe[ri]=!valid_pipe[ri]||ready_pipe[ri+1];
    end endgenerate
    assign s_ready=rstn&&ready_pipe[0]; assign m_valid=rstn&&valid_pipe[PIPE_STAGES-1];
    reg [10:0] x_pipe[0:PIPE_STAGES-1]; reg [9:0] y_pipe[0:PIPE_STAGES-1];
    reg [PIXEL_ID_WIDTH-1:0] id_pipe[0:PIPE_STAGES-1];
    reg [FRAME_ID_WIDTH-1:0] frame_pipe[0:PIPE_STAGES-1];
    reg sof_pipe[0:PIPE_STAGES-1],eol_pipe[0:PIPE_STAGES-1],eof_pipe[0:PIPE_STAGES-1];
    reg [CHANNELS*8-1:0] skip0, branch0;
    reg [39:0] skip_product1[0:CHANNELS-1], branch_product1[0:CHANNELS-1];
    reg [40:0] skip_rounded2[0:CHANNELS-1], branch_rounded2[0:CHANNELS-1];
    reg [39:0] skip_value3[0:CHANNELS-1], branch_value3[0:CHANNELS-1];
    reg [40:0] joined4[0:CHANNELS-1];
    reg [CHANNELS*8-1:0] features4;
    integer ch,st;
    always @(posedge clk or negedge rstn) begin
        if(!rstn) valid_pipe<={PIPE_STAGES{1'b0}};
        else begin
            if(ready_pipe[0]) valid_pipe[0]<=s_valid;
            for(st=1;st<PIPE_STAGES;st=st+1) if(ready_pipe[st]) valid_pipe[st]<=valid_pipe[st-1];
        end
    end
    always @(posedge clk) begin
        if(rstn&&ready_pipe[0]&&s_valid) begin
            x_pipe[0]<=s_x;y_pipe[0]<=s_y;id_pipe[0]<=s_pixel_id;frame_pipe[0]<=s_frame_id;
            sof_pipe[0]<=s_sof;eol_pipe[0]<=s_eol;eof_pipe[0]<=s_eof;
            skip0<=s_skip;branch0<=s_branch;
        end
        for(st=1;st<PIPE_STAGES;st=st+1) if(rstn&&ready_pipe[st]) begin
            x_pipe[st]<=x_pipe[st-1];y_pipe[st]<=y_pipe[st-1];id_pipe[st]<=id_pipe[st-1];
            frame_pipe[st]<=frame_pipe[st-1];sof_pipe[st]<=sof_pipe[st-1];
            eol_pipe[st]<=eol_pipe[st-1];eof_pipe[st]<=eof_pipe[st-1];
        end
        if(rstn&&ready_pipe[1]&&valid_pipe[0]) for(ch=0;ch<CHANNELS;ch=ch+1) begin
            skip_product1[ch]<=skip0[ch*8 +: 8]*skip_mult;
            branch_product1[ch]<=branch0[ch*8 +: 8]*branch_mult;
        end
        if(rstn&&ready_pipe[2]&&valid_pipe[1]) for(ch=0;ch<CHANNELS;ch=ch+1) begin
            skip_rounded2[ch]<=skip_product1[ch]+(40'd1<<(skip_shift-1'b1));
            branch_rounded2[ch]<=branch_product1[ch]+(40'd1<<(branch_shift-1'b1));
        end
        if(rstn&&ready_pipe[3]&&valid_pipe[2]) for(ch=0;ch<CHANNELS;ch=ch+1) begin
            skip_value3[ch]<=skip_rounded2[ch]>>skip_shift;
            branch_value3[ch]<=branch_rounded2[ch]>>branch_shift;
        end
        if(rstn&&ready_pipe[4]&&valid_pipe[3]) for(ch=0;ch<CHANNELS;ch=ch+1) begin
            joined4[ch]<=skip_value3[ch]+branch_value3[ch];
            if((skip_value3[ch]+branch_value3[ch])>255) features4[ch*8 +: 8]<=8'd255;
            else features4[ch*8 +: 8]<=skip_value3[ch][7:0]+branch_value3[ch][7:0];
        end
    end
    assign m_features=features4;assign m_x=x_pipe[PIPE_STAGES-1];assign m_y=y_pipe[PIPE_STAGES-1];
    assign m_pixel_id=id_pipe[PIPE_STAGES-1];assign m_frame_id=frame_pipe[PIPE_STAGES-1];
    assign m_sof=sof_pipe[PIPE_STAGES-1];assign m_eol=eol_pipe[PIPE_STAGES-1];assign m_eof=eof_pipe[PIPE_STAGES-1];
endmodule

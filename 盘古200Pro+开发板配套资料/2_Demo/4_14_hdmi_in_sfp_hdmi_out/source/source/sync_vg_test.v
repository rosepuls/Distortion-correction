`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:Meyesemi 
// Engineer: Will
// 
// Create Date: 2023-01-29 20:31  
// Design Name:  
// Module Name: 
// Project Name: 
// Target Devices: Pango
// Tool Versions: 
// Description: 
//      
// Dependencies: 
//    VS     ______                                       ______
//HS  __    |      |_______________¡­¡­____________________|      |
//   |       h_sync  h_bp       h_act                h_fp
//   |__                    _______________________
//DE    |   _______________|                       |_____________
//      |
//      .
//      |
//    __|
//   |  
//   |__ 
//      |
// 
// Revision:
// Revision 1.0 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`define UD #1
module sync_vg_test # (
    parameter               X_BITS=4'd12,
    parameter               Y_BITS=4'd12,
    parameter               V_TOTAL = 12'd750,
    parameter               V_FP = 12'd5,
    parameter               V_BP = 12'd20,
    parameter               V_SYNC = 12'd5,
    parameter               V_ACT = 12'd720,
    parameter               H_TOTAL = 12'd1650,
    parameter               H_FP = 12'd110,
    parameter               H_BP = 12'd220,
    parameter               H_SYNC = 12'd40,
    parameter               H_ACT = 12'd1280
)(
    input                   clk                 ,
    input                   rstn                ,
//    input                   vs_frame            ,
    output reg              vs_out_2d              ,
    output reg              hs_out_2d              ,
    output reg              de_out              ,
    output reg              de_out_2d              ,
    output reg [X_BITS-1:0] x_act               ,
    output reg [Y_BITS-1:0] y_act               ,
    output reg              f_end               ,
    output reg [15:0]       yuv_data
//
//    input  [12:0]           v_total_o           ,
//    input  [8:0]            v_fp_o              ,
//    input  [8:0]            v_bp_o              ,
//    input  [8:0]            v_sync_o            ,
//    input  [12:0]           v_act_o             ,
//    input  [12:0]           h_total_o           ,
//    input  [12:0]           h_fp_o              ,
//    input  [12:0]           h_bp_o              ,
//    input  [8:0]            h_sync_o            ,
//    input  [12:0]           h_act_o 

);
//  parameter               HV_OFFSET = 12'd0 ;
reg vs_frame_1d;
reg vs_frame_2d;
reg vs_frame;
always @(posedge clk)
begin
    vs_frame_1d <= vs_frame;
    vs_frame_2d <= vs_frame_1d;
end

reg vs_flag;
always @(posedge clk)
begin
    if (!rstn)
        vs_flag<=1'b0;
    else if(!vs_frame_2d && vs_frame_1d)
        vs_flag<=1'b1;
    else
        vs_flag<=vs_flag;
end

reg [19:0]vs_delay_cnt;
always @(posedge clk)
begin
    if (!rstn)
        vs_delay_cnt <= 20'd0;
    else if(!vs_frame_2d && vs_frame_1d && !vs_flag)
        vs_delay_cnt <= 20'd0;
    else if(vs_delay_cnt < H_TOTAL && vs_flag)
        vs_delay_cnt <= vs_delay_cnt + 1'b1;
    else
        vs_delay_cnt <= vs_delay_cnt;
end
wire vs_rstn;
assign vs_rstn=(vs_delay_cnt == H_TOTAL);


    reg [X_BITS-1:0]        h_count = 'd0;
    reg [Y_BITS-1:0]        v_count = 'd0;
    
    /* horizontal counter */
    always @(posedge clk)
    begin
        if (!rstn )
            h_count <= `UD 0;
        else
        begin
            if (h_count < H_TOTAL - 1)
                h_count <= `UD h_count + 1;
            else
                h_count <= `UD 0;
        end
    end
    
    /* vertical counter */
    always @(posedge clk)
    begin
        if (!rstn )
            v_count <= `UD 0;
        else
        if (h_count == H_TOTAL - 1)
        begin
            if (v_count == V_TOTAL - 1)
                v_count <= `UD 0;
            else
                v_count <= `UD v_count + 1;
        end
    end
reg hs_out;
reg vs_out;
    always @(posedge clk)
    begin
        if (!rstn)
            hs_out <= `UD 4'b0;
        else 
            hs_out <= `UD ((h_count < H_SYNC));
    end
    
    always @(posedge clk)
    begin
        if (!rstn )
            vs_out <= `UD 4'b0;
        else 
        begin
            if (v_count == 0)
                vs_out <= `UD 1'b1;
            else if (v_count == V_SYNC)
                vs_out <= `UD 1'b0;
            else
                vs_out <= `UD vs_out;
        end
    end
reg hs_out_1d;
//reg hs_out_2d;
reg vs_out_1d;
reg de_out_1d;
//reg vs_out_2d;
always @(posedge clk)
begin
    hs_out_1d <= hs_out;
    hs_out_2d <= hs_out_1d;
    vs_out_1d <= vs_out;
    vs_out_2d <= vs_out_1d;
    de_out_1d <= de_out;
    de_out_2d <= de_out_1d;
end


    always @(posedge clk)
    begin
        if (!rstn )
            de_out <= `UD 4'b0;
        else
            de_out <= (((v_count >= V_SYNC + V_BP) && (v_count <= V_TOTAL - V_FP - 1)) && 
                      ((h_count >= H_SYNC + H_BP - 2'd2) && (h_count <= H_TOTAL - H_FP - 2'd3)));
    end
//reg [15:0]yuv_data;
    always @(posedge clk)
    begin
        if (!rstn )
            yuv_data <= `UD 16'd0;
        else if(de_out_1d)
            yuv_data <= `UD yuv_data + 1'd1;
        else
            yuv_data <= `UD 16'd0;
    end

    always @(posedge clk)
    begin
        if (!rstn )
            f_end <= `UD 4'b0;
        else
            f_end <= (v_count == V_TOTAL - V_FP - 1) && (h_count == H_TOTAL - H_FP + 2);
    end
    
    // active pixels counter output
    always @(posedge clk)
    begin
        if (!rstn )
            x_act <= `UD 'd0;
        else 
        begin
        /* X coords ¨C for a backend pattern generator */
            if(h_count > (H_SYNC + H_BP - 1'b1))
                x_act <= `UD (h_count - (H_SYNC + H_BP));
            else
                x_act <= `UD 'd0;
        end
    end
    
    always @(posedge clk)
    begin
        if (!rstn )
            y_act <= `UD 'd0;
        else 
        begin
            /* Y coords ¨C for a backend pattern generator */
            if(v_count > (V_SYNC + V_BP - 1'b1))
                y_act <= `UD (v_count - (V_SYNC + V_BP));
            else
                y_act <= `UD 'd0;
        end
    end
    
endmodule

//////////////////////////////////////////////////////////////////////////////////
// Company:Meyesemi 
// Engineer: 
// 
// Create Date: 2024-11-22  
// Design Name: 
// Module Name: pattern_vg
// Project Name: hdmi_dyn_ppll
// Target Devices: Pango PG2L100H-6FBG676
// Tool Versions: PDS 2022.2-SP6.4
// Description: Dynamically control the resolution of HDMI 
//      
// Dependencies: 
// 
// Revision:
// Revision 1.0 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
`define UD #1
module pattern_vg # (
    parameter                            COCLOR_DEPP=8, // number of bits per channel
    parameter                            X_BITS=13,
    parameter                            Y_BITS=13
)(                                       
    input                                rstn, 
    input                                pix_clk,
    input [X_BITS-1:0]                   act_x, 
    input                                vs_in, 
    input                                hs_in, 
    input                                de_in,
    input [12:0]                         v_act,
    input [12:0]                         h_act,
    
    output reg                           vs_out, 
    output reg                           hs_out, 
    output reg                           de_out,
    output reg [COCLOR_DEPP-1:0]         r_out, 
    output reg [COCLOR_DEPP-1:0]         g_out, 
    output reg [COCLOR_DEPP-1:0]         b_out
);

    
    always @(posedge pix_clk)
    begin
        vs_out <= `UD vs_in;
        hs_out <= `UD hs_in;
        de_out <= `UD de_in;
    end

    always @(posedge pix_clk)
    begin
        if (de_in)
        begin
            if(act_x < h_act/8)          
            begin
                r_out <= 8'hff;
                g_out <= 8'hff;
                b_out <= 8'hff;
            end
            else if(act_x < 2* (h_act/8))
            begin
                r_out <= 8'hff;
                g_out <= 8'hff;
                b_out <= 8'h00;
            end
            else if(act_x < 3* (h_act/8))
            begin
                r_out <= 8'h00;
                g_out <= 8'hff;
                b_out <= 8'hff;
            end
            else if(act_x < 4* (h_act/8))
            begin
                r_out <= 8'h00;
                g_out <= 8'hff;
                b_out <= 8'h00;
            end
            else if(act_x < 5* (h_act/8))
            begin
                r_out <= 8'hff;
                g_out <= 8'h00;
                b_out <= 8'hff;
            end
            else if(act_x < 6* (h_act/8))
            begin
                r_out <= 8'hff;
                g_out <= 8'h00;
                b_out <= 8'h00;
            end
            else if(act_x < 7* (h_act/8))      
            begin
                r_out <= 8'h00;
                g_out <= 8'h00;
                b_out <= 8'hff;
            end
            else
            begin
                r_out <= 8'h0;                  
                g_out <= 8'h0;
                b_out <= 8'h0;
            end
        end
        else
        begin
            r_out <= 8'h00;
            g_out <= 8'h00;
            b_out <= 8'h00;
        end
    end
    
endmodule

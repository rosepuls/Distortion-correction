
//////////////////////////////////////////////////////////////////////////////////
// Company:Meyesemi 
// Engineer: 
// 
// Create Date: 2024-11-22  
// Design Name: 
// Module Name: sync_vg
// Project Name: hdmi_dyn_ppll
// Target Devices: Pango PG2L100H-6FBG676
// Tool Versions: PDS 2022.2-SP6.4
// Description: 
//      
// Dependencies: 
//    VS     ______                                       ______
//HS  __    |      |_______________����____________________|      |
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
`timescale 1ns / 1ps
`define UD #1
`define NO_SIM
module sync_vg(
    input                   clk,                   
    input                   rstn,
    input            [7:0]  key_cnt,
    output reg              vs_out,               
    output reg              hs_out,                   
    output reg              de_out,                   
    output reg [12:0] x_act,                   
    output reg [12:0] y_act,
    output reg       [12:0] h_act,
    output reg       [12:0] v_act            
);
//////////////////////////////////////////////////////////////

reg [12:0]  v_total;
reg [8:0]   v_fp;
reg [8:0]   v_bp;
reg [8:0]   v_sync;
//reg [12:0]  v_act;
reg [12:0]  h_total;
reg [12:0]  h_fp;
reg [12:0]  h_bp;
reg [8:0]   h_sync;
//reg [12:0]  h_act;
reg [5:0]   fram;

`ifdef SIM
always @(posedge clk)
begin
    v_total <= 13'd50;
    v_fp    <= 8'd5;
    v_bp    <= 8'd5;
    v_sync  <= 8'd5;
    v_act   <= 13'd35;
    h_total <= 13'd50;
    h_fp    <= 13'd5;
    h_bp    <= 13'd5;
    h_sync  <= 8'd5;
    h_act   <= 13'd35;
    fram    <= 6'd60;
end
`elsif NO_SIM

always @(posedge clk)
begin
    case(key_cnt)
    8'd1://1280*800P60    pixclk=83.5M//88.8
        begin
            v_total <= 13'd831;
            v_fp    <= 8'd3;
            v_bp    <= 8'd22;
            v_sync  <= 8'd6;
            v_act   <= 13'd800;
            h_total <= 13'd1680;
            h_fp    <= 13'd72;
            h_bp    <= 13'd200;
            h_sync  <= 8'd128;
            h_act   <= 13'd1280;
            fram    <= 6'd60;
        end
    8'd2://1360*768P60	    pixclk=85.5M
        begin
            v_total <= 13'd795;
            v_fp    <= 8'd3;
            v_bp    <= 8'd18;
            v_sync  <= 8'd6;
            v_act   <= 13'd768;
            h_total <= 13'd1792;
            h_fp    <= 13'd64;
            h_bp    <= 13'd256;
            h_sync  <= 8'd112;
            h_act   <= 13'd1360;
            fram    <= 6'd60;
        end
    8'd3://1400*1050P60	    pixclk=101M
        begin
            v_total <= 13'd1080;
            v_fp    <= 8'd3;
            v_bp    <= 8'd23;
            v_sync  <= 8'd4;
            v_act   <= 13'd1050;
            h_total <= 13'd1560;
            h_fp    <= 13'd48;
            h_bp    <= 13'd80;
            h_sync  <= 8'd32;
            h_act   <= 13'd1400;
            fram    <= 6'd60;
        end
    8'd4://1440*900P60	    pixclk=88.75M//174.1
        begin
            v_total <= 13'd926;
            v_fp    <= 8'd3;
            v_bp    <= 8'd17;
            v_sync  <= 8'd6;
            v_act   <= 13'd900;
            h_total <= 13'd1600;
            h_fp    <= 13'd48;
            h_bp    <= 13'd80;
            h_sync  <= 8'd32;
            h_act   <= 13'd1440;
            fram    <= 6'd60;
        end
    8'd5://1600*900P60	    pixclk=108M
        begin
            v_total <= 13'd1000;
            v_fp    <= 8'd1;
            v_bp    <= 8'd96;
            v_sync  <= 8'd3;
            v_act   <= 13'd900;
            h_total <= 13'd1800;
            h_fp    <= 13'd24;
            h_bp    <= 13'd96;
            h_sync  <= 8'd80;
            h_act   <= 13'd1600;
            fram    <= 6'd60;
        end
    8'd6://1600*1200P60    pixclk=162M
        begin
            v_total <= 13'd1250;
            v_fp    <= 8'd1;
            v_bp    <= 8'd46;
            v_sync  <= 8'd3;
            v_act   <= 13'd1200;
            h_total <= 13'd2160;
            h_fp    <= 13'd64;
            h_bp    <= 13'd304;////////////////////////
            h_sync  <= 8'd192;
            h_act   <= 13'd1600;
            fram    <= 6'd60;
        end
    8'd7://1680*1050P60    pixclk=119M
        begin
            v_total <= 13'd1080;
            v_fp    <= 8'd3;
            v_bp    <= 8'd21;
            v_sync  <= 8'd6;
            v_act   <= 13'd1050;
            h_total <= 13'd1840;
            h_fp    <= 13'd48;
            h_bp    <= 13'd80;
            h_sync  <= 8'd32;
            h_act   <= 13'd1680;
            fram    <= 6'd60;
        end
    8'd8://1280*720P60    pixclk=74.25M
        begin
            v_total <= 13'd750;
            v_fp    <= 8'd5;
            v_bp    <= 8'd20;
            v_sync  <= 8'd5;
            v_act   <= 13'd720;
            h_total <= 13'd1650;
            h_fp    <= 13'd110;
            h_bp    <= 13'd220;
            h_sync  <= 8'd40;
            h_act   <= 13'd1280;
            fram    <= 6'd60;
        end
    8'd9://1920*1080P60    pixclk=148.5M
        begin
            v_total <= 13'd1125;
            v_fp    <= 8'd4;
            v_bp    <= 8'd36;
            v_sync  <= 8'd5;
            v_act   <= 13'd1080;
            h_total <= 13'd2200;
            h_fp    <= 13'd88;
            h_bp    <= 13'd148;
            h_sync  <= 8'd44;
            h_act   <= 13'd1920;
            fram    <= 6'd60;
        end
    8'd10://1920*1200P60    pixclk=154M
        begin
            v_total <= 13'd1235;
            v_fp    <= 8'd3;
            v_bp    <= 8'd26;
            v_sync  <= 8'd6;
            v_act   <= 13'd1200;
            h_total <= 13'd2080;
            h_fp    <= 13'd48;
            h_bp    <= 13'd80;
            h_sync  <= 8'd32;
            h_act   <= 13'd1920;
            fram    <= 6'd60;
        end
    default://1080P60    pixclk=148.5M
        begin
            v_total <= 13'd1125;
            v_fp    <= 8'd4;
            v_bp    <= 8'd36;
            v_sync  <= 8'd5;
            v_act   <= 13'd1080;
            h_total <= 13'd2200;
            h_fp    <= 13'd88;
            h_bp    <= 13'd148;
            h_sync  <= 8'd44;
            h_act   <= 13'd1920;
            fram    <= 6'd60;          
        end
    endcase
end
`endif

//////////////////////////////////////////////////////////////
//    parameter               HV_OFFSET = 12'd0 ;
    reg [12:0]        h_count = 'd0;
    reg [12:0]        v_count = 'd0;
    
    /* horizontal counter */
    always @(posedge clk)
    begin
        if (!rstn)
            h_count <= `UD 0;
        else
        begin
            if (h_count < h_total - 1)
                h_count <= `UD h_count + 1;
            else
                h_count <= `UD 0;
        end
    end
    
    /* vertical counter */
    always @(posedge clk)
    begin
        if (!rstn)
            v_count <= `UD 0;
        else
        if (h_count == h_total - 1)
        begin
            if (v_count == v_total - 1)
                v_count <= `UD 0;
            else
                v_count <= `UD v_count + 1;
        end
    end
    //  horizontal sync  //
    always @(posedge clk)
    begin
        if (!rstn)
            hs_out <= `UD 4'b0;
        else 
            hs_out <= `UD ((h_count < h_sync));
    end
    //   vertical sync  //
    always @(posedge clk)
    begin
        if (!rstn)
            vs_out <= `UD 4'b0;
        else 
        begin
            if (v_count == 0)
                vs_out <= `UD 1'b1;
            else if (v_count == v_sync)
                vs_out <= `UD 1'b0;
            else
                vs_out <= `UD vs_out;
        end
    end
    //    Data Valid   //
    always @(posedge clk)
    begin
        if (!rstn)
            de_out <= `UD 4'b0;
        else
            de_out <= (((v_count >= v_sync + v_bp) && (v_count <= v_total - v_fp - 1)) && 
                      ((h_count >= h_sync + h_bp) && (h_count <= h_total - h_fp - 1)));
    end
    
    // active pixels counter output
    always @(posedge clk)
    begin
        if (!rstn)
            x_act <= `UD 'd0;
        else 
        begin
        /* X coords �C for a backend pattern generator */
            if(h_count > (h_sync + h_bp - 1'b1))
                x_act <= `UD (h_count - (h_sync + h_bp));
            else
                x_act <= `UD 'd0;
        end
    end
    
    always @(posedge clk)
    begin
        if (!rstn)
            y_act <= `UD 'd0;
        else 
        begin
            /* Y coords �C for a backend pattern generator */
            if(v_count > (v_sync + v_bp - 1'b1))
                y_act <= `UD (v_count - (v_sync + v_bp));
            else
                y_act <= `UD 'd0;
        end
    end
    
endmodule

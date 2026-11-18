//////////////////////////////////////////////////////////////////////////////////
// Company:Meyesemi 
// Engineer: 
// 
// Create Date: 2024-11-22  
// Design Name: 
// Module Name: key_ctl
// Project Name: hdmi_dyn_ppll
// Target Devices: Pango PG2L100H-6FBG676
// Tool Versions: PDS 2022.2-SP6.4
// Description:  
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
`define NO_SIM
module key_ctl(
    input            clk,
    input            key,
    output           key_deb,
    output     [7:0] key_cnt
);
`ifdef SIM
parameter DELAY=20'h10;
`elsif NO_SIM
parameter DELAY=20'h7_ffff;
`endif

    wire btn_deb;
    // °´¼üÏû¶¶
    btn_deb_fix#(                    
        .BTN_WIDTH   (  4'd1        ), //parameter                  BTN_WIDTH = 4'd8
        .BTN_DELAY   (  DELAY       )
    ) u_btn_deb                           
    (                            
        .clk         (  clk         ),//input                      clk,
        .btn_in      (  key         ),//input      [BTN_WIDTH-1:0] btn_in,
                                    
        .btn_deb_fix (  btn_deb     ) //output reg [BTN_WIDTH-1:0] btn_deb
    );
assign key_deb=btn_deb;
    reg btn_deb_1d;
    always @(posedge clk)
    begin
        btn_deb_1d <= `UD btn_deb;
    end

    reg [7:0]  key_push_cnt=2'd0;
    always @(posedge clk)
    begin
        if(~btn_deb & btn_deb_1d)
        begin
            if(key_push_cnt == 8'd10)
                key_push_cnt <= `UD 2'd1;
            else
                key_push_cnt <= `UD key_push_cnt + 2'd1;
        end
    end
    
    assign key_cnt = key_push_cnt;

endmodule

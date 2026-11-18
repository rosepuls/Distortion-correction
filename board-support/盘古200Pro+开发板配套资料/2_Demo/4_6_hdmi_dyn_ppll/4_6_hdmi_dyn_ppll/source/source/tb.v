//////////////////////////////////////////////////////////////////////////////////
// Company:Meyesemi 
// Engineer: 
// 
// Create Date: 2024-11-22  
// Design Name: 
// Module Name: tb
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
module tb(

   );
reg sys_clk;
reg rstn_key;
reg key;

wire lock_led;
wire pix_clk;
wire vs_out;
wire hs_out;
wire de_out;
wire [7:0]r_out;
wire [7:0]g_out;
wire [7:0]b_out;

// sys_clk generation
initial
begin
    sys_clk = 0;
    forever #(20) sys_clk = ~sys_clk;
end

// reset and key generation
initial
begin
    rstn_key  = 1'b0;
    key       = 1'b1;
    #100
    rstn_key  = 1'b1;
end

always @(posedge sys_clk)
begin
    if(!rstn_key)
        key <= 1'b1;
    else
        key <= ~vs_out;//test:switch resolution once per frame of image
end
GTP_GRS GRS_INST(
    .GRS_N(1'b1)
    ) ;
hdmi_dyn_ppll hdmi_dyn_ppll(
    .sys_clk(sys_clk),        // input
    .rstn_key(rstn_key),      // input
    .key(key),                // input

    .lock_led(lock_led),      // output
    .pix_clk(pix_clk),        // output
    .vs_out(vs_out),          // output
    .hs_out(hs_out),          // output
    .de_out(de_out),          // output
    .r_out(r_out),            // output[7:0]
    .g_out(g_out),            // output[7:0]
    .b_out(b_out)             // output[7:0]
);

endmodule
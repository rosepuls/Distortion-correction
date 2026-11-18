/////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2019 PANGO MICROSYSTEMS, INC
// ALL RIGHTS REVERVED.
//
// THE SOURCE CODE CONTAINED HEREIN IS PROPRIETARY TO PANGO MICROSYSTEMS, INC.
// IT SHALL NOT BE REPRODUCED OR DISCLOSED IN WHOLE OR IN PART OR USED BY
// PARTIES WITHOUT WRITTEN AUTHORIZATION FROM THE OWNER.
//
//////////////////////////////////////////////////////////////////////////////

`timescale 1ns/10fs
module ipmxe_loadsc_n_gen_v1_0(
    input    wire    clk,
    input    wire    rst_n,
    input    wire    adc_loadsc_n,
    output   wire    o_loadsc_n
);

reg [7:0]  count;
reg        count_flag;
reg        count_flag_p;
wire       flag_loadsc_n;
reg        i_loadsc_n_p1;
reg        i_loadsc_n_p2;
wire       loadsc_n_flag;
reg        loadsc_n_p;

always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        i_loadsc_n_p1 <= 1'b1;
        i_loadsc_n_p2 <= 1'b1;
    end
    else
    begin
        i_loadsc_n_p1 <= adc_loadsc_n;
        i_loadsc_n_p2 <= i_loadsc_n_p1;
    end
end

always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        count <= 1'b0;
    end
    else if(count < 8'hff)
    begin
        count <= count + 1'b1;
    end
    else
    begin
        count <= count;
    end
end

always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        count_flag   <= 1'b0;
        count_flag_p <= 1'b0;
    end
    else if(count == 8'hff)
    begin
        count_flag   <= 1'b1;
        count_flag_p <= count_flag;
    end
    else
    begin
        count_flag <= count_flag;
        count_flag_p <= count_flag_p;
    end
end

assign flag_loadsc_n = (~count_flag) || count_flag_p;

assign loadsc_n_flag = i_loadsc_n_p2 && flag_loadsc_n;

always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        loadsc_n_p <= 1'b1;
    else
        loadsc_n_p <= loadsc_n_flag;
end

assign o_loadsc_n = loadsc_n_flag && loadsc_n_p;

endmodule

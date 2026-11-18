`timescale 1ns / 1ps
/*/////////////////////////////////////////////////////////////////////////////////
    parameter TX_KCHAR          = 4'h1                 ,//TX_KCHARπ≤”√
    parameter IDLE_FRAME        = 32'h0605_04bc        ,//ø’œ–÷°
*//////////////////////////////////////////////////////////////////////////////////
`define UD #1
module word_align (
    input              rx_clk           ,
    input              rstn             ,
               
    input      [31:0]  rx_data          ,
    input      [ 3:0]  rx_ctrl          ,
    
    output reg [31:0]  rx_data_align    ,
    output reg [ 3:0]  rx_ctrl_align
);
//////////////////////////////////////////////////////////////////////////////////
    reg [31:0]  rx_data_1d;
    reg [ 3:0]  rx_ctrl_1d;
    reg [ 3:0]  align_bit;
//////////////////////////////////////////////////////////////////////////////////
    always @(posedge rx_clk)
    begin
        rx_data_1d <= rx_data;
        rx_ctrl_1d <= rx_ctrl;
    end 
//////////////////////////////////////////////////////////////////////////////////    
    always @(posedge rx_clk)
    begin
        if(!rstn)
            align_bit <= 4'b0;
        else if(rx_ctrl != 4'b0)
            align_bit <= rx_ctrl;
        else
            align_bit <= align_bit;
    end 
    
    always @(posedge rx_clk)
    begin
        if(!rstn)
            rx_data_align <= 32'd0;
        else 
        begin 
            case (align_bit)
                4'b0001   :  rx_data_align <= rx_data;
                4'b0010   :  rx_data_align <= {rx_data[7:0],rx_data_1d[31:8]};
                4'b0100   :  rx_data_align <= {rx_data[15:0],rx_data_1d[31:16]};
                4'b1000   :  rx_data_align <= {rx_data[23:0],rx_data_1d[31:24]};
               default    :  rx_data_align <=  32'd0;
            endcase
        end 
    end
    
    always @(posedge rx_clk)
    begin
        if(!rstn)
            rx_ctrl_align <= 4'd0;
        else 
        begin 
            case (align_bit)
                4'b0001   :  rx_ctrl_align <= rx_ctrl;
                4'b0010   :  rx_ctrl_align <= {rx_ctrl[0],rx_ctrl_1d[3:1]};
                4'b0100   :  rx_ctrl_align <= {rx_ctrl[1:0],rx_ctrl_1d[3:2]};
                4'b1000   :  rx_ctrl_align <= {rx_ctrl[2:0],rx_ctrl_1d[3]};
               default    :  rx_ctrl_align <=  4'd0;
            endcase
        end 
    end  

endmodule

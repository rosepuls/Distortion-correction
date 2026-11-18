
//////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2019 PANGO MICROSYSTEMS, INC
// ALL RIGHTS REVERVED.
//
// THE SOURCE CODE CONTAINED HEREIN IS PROPRIETARY TO PANGO MICROSYSTEMS, INC.
// IT SHALL NOT BE REPRODUCED OR DISCLOSED IN WHOLE OR IN PART OR USED BY
// PARTIES WITHOUT WRITTEN AUTHORIZATION FROM THE OWNER.
//
//////////////////////////////////////////////////////////////////////////////
//               
// Library:
// Filename:<iname />.v                 
//////////////////////////////////////////////////////////////////////////////
`timescale 1ns/10fs

module adc_test (

    
//clk and rst_n
    input    wire           i_rst_n,
    input    wire           i_apb_clk,
//APB Interface
    input    wire  [7:0]    i_apb_paddr,
    input    wire           i_apb_psel,
    input    wire           i_apb_enable,
    input    wire           i_apb_pwrite,
    input    wire  [15:0]   i_apb_pwdata,
    output   wire  [15:0]   o_apb_prdata,
    output   wire           o_apb_pready,
    //Control and Status Interface

    input    wire           i_adc_loadsc_n,

    output   wire           o_logic_done_a,
    output   wire           o_logic_done_b,
    output   wire           o_adc_clk_out,
    output   wire           o_adc_dmodified
);

//Parameter
//Control Reg

localparam  [15:0]    CREG_00H = 16'b1011001100000000;

localparam  [15:0]    CREG_01H = 16'b1101000000011111;

localparam  [15:0]    CREG_02H = 16'b0010000000000000;

//Channel Sequence Reg

localparam  [15:0]    CREG_03H = 16'b0000000001111100;

localparam  [15:0]    CREG_04H = 16'b0000000000000000;

localparam  [15:0]    CREG_05H = 16'b0000000000000000;

localparam  [15:0]    CREG_06H = 16'b0000000000000000;

localparam  [15:0]    CREG_07H = 16'b0000000001111100;

localparam  [15:0]    CREG_08H = 16'b0000000000000000;

localparam  [15:0]    CREG_0AH = 16'b0000000000000000;

localparam  [15:0]    CREG_0CH = 16'b0000000000000000;

localparam  [15:0]    CREG_0EH = 16'b0000000000000000;

//Alarm Set Reg

localparam  [11:0]    CREG_20H = 12'b100011000000;

localparam  [11:0]    CREG_21H = 12'b100011000000;

localparam  [11:0]    CREG_22H = 12'b000000000000;

localparam  [11:0]    CREG_23H = 12'b000000000000;

localparam  [11:0]    CREG_24H = 12'b000000000000;

localparam  [11:0]    CREG_25H = 12'b000000000000;

localparam  [11:0]    CREG_26H = 12'b000000000000;

localparam  [11:0]    CREG_27H = 12'b000000000000;

localparam  [11:0]    CREG_28H = 12'b000000000000;

localparam  [11:0]    CREG_29H = 12'b000000000000;

localparam  [11:0]    CREG_2AH = 12'b110011000010;

localparam  [11:0]    CREG_2BH = 12'b101001011011;

localparam  [13:0]    CREG_31H = 14'h0000;


    wire [1:0]  i_va;
    wire [31:0] i_vaux;

    wire [4:0]  o_adc_alarm;

    wire        i_vap;
    wire        i_van;

    wire        i_vauxp0;
    wire        i_vauxn0;

    wire        i_vauxp1;
    wire        i_vauxn1;

    wire        i_vauxp2;
    wire        i_vauxn2;

    wire        i_vauxp3;
    wire        i_vauxn3;

    wire        i_vauxp4;
    wire        i_vauxn4;

    wire        i_vauxp5;
    wire        i_vauxn5;

    wire        i_vauxp6;
    wire        i_vauxn6;

    wire        i_vauxp7;
    wire        i_vauxn7;

    wire        i_vauxp8;
    wire        i_vauxn8;

    wire        i_vauxp9;
    wire        i_vauxn9;

    wire        i_vauxp10;
    wire        i_vauxn10;

    wire        i_vauxp11;
    wire        i_vauxn11;

    wire        i_vauxp12;
    wire        i_vauxn12;

    wire        i_vauxp13;
    wire        i_vauxn13;

    wire        i_vauxp14;
    wire        i_vauxn14;

    wire        i_vauxp15;
    wire        i_vauxn15;

    wire        i_adc_convst;

    wire        o_over_temp;

    wire        o_user_temp_alarm;

    wire        o_vcc_alarm;

    wire        o_vcca_alarm;

    wire        o_vcc_cram_alarm;

    wire        o_vcc_drm_alarm;

    wire        o_vcc_pu_alarm;

    wire        o_vcca_pu_alarm;

    wire        o_vccio_ddr_alarm;

    wire        o_rst_n_sync;
    wire        o_loadsc_n;


assign    i_vap = 1'b0;
assign    i_van = 1'b0;

assign    i_vauxp0 = 1'b0;
assign    i_vauxn0 = 1'b0;

assign    i_vauxp1 = 1'b0;
assign    i_vauxn1 = 1'b0;

assign    i_vauxp2 = 1'b0;
assign    i_vauxn2 = 1'b0;

assign    i_vauxp3 = 1'b0;
assign    i_vauxn3 = 1'b0;

assign    i_vauxp4 = 1'b0;
assign    i_vauxn4 = 1'b0;

assign    i_vauxp5 = 1'b0;
assign    i_vauxn5 = 1'b0;

assign    i_vauxp6 = 1'b0;
assign    i_vauxn6 = 1'b0;

assign    i_vauxp7 = 1'b0;
assign    i_vauxn7 = 1'b0;

assign    i_vauxp8 = 1'b0;
assign    i_vauxn8 = 1'b0;

assign    i_vauxp9 = 1'b0;
assign    i_vauxn9 = 1'b0;

assign    i_vauxp10 = 1'b0;
assign    i_vauxn10 = 1'b0;

assign    i_vauxp11 = 1'b0;
assign    i_vauxn11 = 1'b0;

assign    i_vauxp12 = 1'b0;
assign    i_vauxn12 = 1'b0;

assign    i_vauxp13 = 1'b0;
assign    i_vauxn13 = 1'b0;

assign    i_vauxp14 = 1'b0;
assign    i_vauxn14 = 1'b0;

assign    i_vauxp15 = 1'b0;
assign    i_vauxn15 = 1'b0;

assign    i_adc_convst = 1'b0;

assign    i_va = {i_vap,i_van};

assign    i_vaux = {i_vauxp15,i_vauxn15,i_vauxp14,i_vauxn14,i_vauxp13,i_vauxn13,i_vauxp12,i_vauxn12,i_vauxp11,i_vauxn11,i_vauxp10,i_vauxn10,i_vauxp9,i_vauxn9,i_vauxp8,i_vauxn8,i_vauxp7,i_vauxn7,i_vauxp6,i_vauxn6,i_vauxp5,i_vauxn5,i_vauxp4,i_vauxn4,i_vauxp3,i_vauxn3,i_vauxp2,i_vauxn2,i_vauxp1,i_vauxn1,i_vauxp0,i_vauxn0};

assign    {o_vcc_cram_alarm,o_vcc_drm_alarm,o_vcca_alarm,o_vcc_alarm,o_user_temp_alarm} = o_adc_alarm;


ipmxe_adc_sync_v1_0  rstn_sync (.clk(i_apb_clk),  .rst_n(i_rst_n), .sig_async(1'b1), .sig_synced (o_rst_n_sync) );

ipmxe_loadsc_n_gen_v1_0  u_loadsc_n_gen (
    .clk               (i_apb_clk),
    .rst_n             (o_rst_n_sync),
    .adc_loadsc_n      (i_adc_loadsc_n),
    .o_loadsc_n        (o_loadsc_n)
    );


GTP_ADC_E2 #(
    .CREG_00H          (CREG_00H),
    .CREG_01H          (CREG_01H),
    .CREG_02H          (CREG_02H),
    .CREG_03H          (CREG_03H),
    .CREG_04H          (CREG_04H),
    .CREG_05H          (CREG_05H),
    .CREG_06H          (CREG_06H),
    .CREG_07H          (CREG_07H),
    .CREG_08H          (CREG_08H),
    .CREG_0AH          (CREG_0AH),
    .CREG_0CH          (CREG_0CH),
    .CREG_0EH          (CREG_0EH),
    .CREG_20H          (CREG_20H),
    .CREG_21H          (CREG_21H),
    .CREG_22H          (CREG_22H),
    .CREG_23H          (CREG_23H),
    .CREG_24H          (CREG_24H),
    .CREG_25H          (CREG_25H),
    .CREG_26H          (CREG_26H),
    .CREG_27H          (CREG_27H),
    .CREG_28H          (CREG_28H),
    .CREG_29H          (CREG_29H),
    .CREG_2AH          (CREG_2AH),
    .CREG_2BH          (CREG_2BH),
    .CREG_31H          (CREG_31H)
)    u_GTP_ADC (
    .VA                (i_va),
    .VAUX              (i_vaux),
    .DCLK              (i_apb_clk),
    .DADDR             (i_apb_paddr),
    .DEN               (i_apb_psel),
    .SECEN             (i_apb_enable),
    .DWE               (i_apb_pwrite),
    .DI                (i_apb_pwdata),
    .DO                (o_apb_prdata),
    .DRDY              (o_apb_pready),
    .CONVST            (i_adc_convst),
    .RST_N             (o_rst_n_sync),
    .LOADSC_N          (o_loadsc_n),
    .OVER_TEMP         (o_over_temp),
    .LOGIC_DONE_A      (o_logic_done_a),
    .LOGIC_DONE_B      (o_logic_done_b),
    .ADC_CLK_OUT       (o_adc_clk_out),
    .DMODIFIED         (o_adc_dmodified),
    .ALARM             (o_adc_alarm)
);


endmodule

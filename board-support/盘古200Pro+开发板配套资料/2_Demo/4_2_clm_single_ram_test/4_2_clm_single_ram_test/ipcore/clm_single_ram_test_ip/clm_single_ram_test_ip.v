
//////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2014 PANGO MICROSYSTEMS, INC
// ALL RIGHTS REVERVED.
//
// THE SOURCE CODE CONTAINED HEREIN IS PROPRIETARY TO PANGO MICROSYSTEMS, INC.
// IT SHALL NOT BE REPRODUCED OR DISCLOSED IN WHOLE OR IN PART OR USED BY
// PARTIES WITHOUT WRITTEN AUTHORIZATION FROM THE OWNER.
//
//////////////////////////////////////////////////////////////////////////////
//
// Library:
// Filename:clm_single_ram_test_ip.v
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps
module clm_single_ram_test_ip
    (
     wr_data     ,
     rd_data     ,
     addr        ,
     wr_en       ,
     rst         ,
     clk
     );


    localparam ADDR_WIDTH = 5 ; //@IPC int 4,10

    localparam DATA_WIDTH = 2 ; //@IPC int 1,256

    localparam RST_TYPE = "ASYNC" ; //@IPC enum ASYNC,SYNC

    localparam OUT_REG = 0 ; //@IPC bool

    localparam INIT_ENABLE = 0 ; //@IPC bool

    localparam INIT_FILE = "NONE" ; //@IPC string

    localparam FILE_FORMAT = "BIN" ; //@IPC enum BIN,HEX


    input   wire    [DATA_WIDTH-1:0]       wr_data      ;
    output  wire    [DATA_WIDTH-1:0]       rd_data      ;
    input   wire    [ADDR_WIDTH-1:0]       addr         ;
    input   wire                           clk          ;
    input   wire                           wr_en        ;
    input   wire                           rst          ;

ipm_distributed_spram_v1_3_clm_single_ram_test_ip
   #(
     .ADDR_WIDTH    (ADDR_WIDTH )   , //address width   range:4-10
     .DATA_WIDTH    (DATA_WIDTH )   , //data width      range:4-256
     .RST_TYPE      (RST_TYPE   )   , //reset type   "ASYNC_RESET" "SYNC_RESET"
     .OUT_REG       (OUT_REG    )   , //output options :non_register(0)  register(1)
     .INIT_FILE     (INIT_FILE  )   , //legal value:"NONE" or "initial file name"
     .FILE_FORMAT   (FILE_FORMAT)     //initial data format : "bin" or "hex"
    )u_ipm_distributed_spram_clm_single_ram_test_ip
    (
     .wr_data       (wr_data   )    ,
     .rd_data       (rd_data   )    ,
     .addr          (addr      )    ,
     .clk           (clk       )    ,
     .wr_en         (wr_en     )    ,
     .rst           (rst       )
    );

endmodule



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
// Filename:TB clm_single_ram_test_ip_tb.v
//////////////////////////////////////////////////////////////////////////////

`timescale   1ns / 1ps

module  clm_single_ram_test_ip_tb ();

    localparam T_CLK_PERIOD  = 10  ;       //clock a half perid
    localparam T_RST_TIME    = 200 ;       //reset time


    localparam ADDR_WIDTH    = 5 ; //@IPC int 4,10

    localparam DATA_WIDTH    = 2 ; //@IPC int 1,256

    localparam RST_TYPE      = "ASYNC" ; //@IPC enum ASYNC,SYNC

    localparam OUT_REG       = 0 ; //@IPC bool

    localparam INIT_ENABLE   = 0 ; //@IPC bool

    localparam INIT_FILE     = "NONE" ; //@IPC string

    localparam FILE_FORMAT   = "BIN" ; //@IPC enum BIN,HEX



// variable declaration
    reg                       clk_tb     ;
    reg                       check_err  ;
    reg   [2:0]               results_cnt;
    reg                       tb_rst     ;
    reg   [ADDR_WIDTH-1:0]    tb_addr    ;
    reg   [DATA_WIDTH-1:0]    tb_wrdata  ;
    wire  [DATA_WIDTH-1:0]    tb_rddata  ;
    reg                       tb_wr_en   ;


//************************************************************ CGU ****************************************************************************
//generate clk_tb
initial
begin

    clk_tb = 0;
    forever #(T_CLK_PERIOD/2)  clk_tb = ~clk_tb;
end


//********************************************************* DGU ********************************************************************************


task write_spram;
   integer i;

   begin
     tb_wr_en    = 0;
     tb_wrdata   = 0;
     tb_addr     = 0;
     i           = 0;
     while ( i < 2**ADDR_WIDTH )
     begin
        @(posedge clk_tb);
        tb_wr_en  = 1'b1;
        tb_wrdata = ~tb_wrdata;
        tb_addr   = tb_addr + 1'b1;
        i         = i +1'b1;
     end

     tb_wr_en = 1'b0;

   end
endtask

task read_spram;
   integer  init_fid;
   integer j;
   begin
     tb_wr_en = 0;
     tb_addr  = 0;
     init_fid = $fopen ("init_results.dat","a");
     j        = 0;
     while (j < 2**ADDR_WIDTH )
     begin
        @(posedge clk_tb);
         tb_wr_en = 1'b0;
         tb_addr  = tb_addr + 1'b1;
         j        = j + 1'b1;
         $fmonitor(init_fid,"%b",tb_rddata);
     end
   end
endtask

initial begin

   tb_addr     = 0;
   tb_wrdata   = 0;
   tb_wr_en    = 0;

   tb_rst        = 1;
   #T_RST_TIME     ;
   tb_rst        = 0;
   if(INIT_FILE == "NONE") begin
      $display("writing spram");
      write_spram;
      #10;

      $display("reading spram");
      read_spram;
      #10;

      $display("spram simulation done");
   end
   else begin
      $display("reading initialized spram");
      read_spram;
      #10;
      $display("spram simulation done");
   end
   if (|results_cnt)
       $display("Simulation Failed due to Error Found.") ;
   else
       $display("Simulation Success.") ;
   #500;
   $finish ;
end


//***************************************************************** DUT  INST **************************************************************************************
always@(posedge clk_tb or posedge tb_rst) begin
    if(tb_rst)
        check_err <=0;
    else if(INIT_FILE == "NONE")
    begin
        if(tb_wr_en == 1'b0 && OUT_REG == 0)
        begin
            if(tb_addr > 2 && tb_addr%2 == 0 && tb_rddata != 0)
                check_err <=1;
            else
                check_err <=0;
        end
        else if(tb_wr_en == 1'b0 && OUT_REG == 1)
        begin
            if(tb_addr > 2 && tb_addr%2 == 0 && tb_rddata == 0)
                check_err <=1;
            else
                check_err <=0;
        end
    end
    else
        check_err <=0;
end

always @(posedge clk_tb or posedge tb_rst)
begin
    if (tb_rst)
        results_cnt <= 3'b000 ;
    else if (&results_cnt)
        results_cnt <= 3'b100 ;
    else if (check_err)
        results_cnt <= results_cnt + 3'd1 ;
end

integer  result_fid;
initial begin
     result_fid = $fopen ("sim_results.log","a");
     $fmonitor(result_fid,"err_chk=%b",check_err);
end

GTP_GRS GRS_INST(
.GRS_N(1'b1)
);
clm_single_ram_test_ip  U_clm_single_ram_test_ip (
    .addr        (tb_addr   ),          //input  wire [`T_A_ADDR_WIDTH-1 : 0]
    .wr_data     (tb_wrdata ),          //input  wire [`T_A_DATA_WIDTH-1 : 0]
    .rd_data     (tb_rddata ),          //output wire [`T_A_DATA_WIDTH-1 : 0]
    .wr_en       (tb_wr_en  ),          //input  wire
    .rst         (tb_rst    ),          //input  wire
    .clk         (clk_tb    )
);
endmodule


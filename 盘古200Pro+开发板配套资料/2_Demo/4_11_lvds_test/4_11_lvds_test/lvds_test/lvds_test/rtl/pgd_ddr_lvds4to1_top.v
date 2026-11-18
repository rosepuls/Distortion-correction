module pgd_ddr_lvds4to1_top #(
   parameter CHAN_N  = 4,
   parameter PATTERN = 4'b1001
) (
   //system signal
   input                  ref_clk         ,
   input				  dbg_key_oper    ,
   input                  rstn_in         ,
   output [  CHAN_N-1:0]  tx_data_p       ,
   output [  CHAN_N-1:0]  tx_data_n       ,
   output                 tx_clk_p        ,
   output                 tx_clk_n        ,
   //rx domain
   input [  CHAN_N-1:0]    rx_data_p       ,
   input [  CHAN_N-1:0]    rx_data_n       ,
   input                   rx_clk_p        ,
   input                   rx_clk_n        ,
   output                  err_flag                   
);
 
 wire     ref_clk_r ;
 wire [15:0]     pdata;

 wire     sysclk      ;
 wire     rstn_sys    ;
 wire     tx_ioclk    ;
 wire     tx_gtp_rstn ;
 wire     [  CHAN_N-1:0]   err_led ;

wire      rst_n ;
 
 wire                  rx_train_done   /* synthesis syn_keep=1 */;
 wire                  tx_train_done   ;
 wire  [4*CHAN_N-1:0]  tx_data         /*synthesis PAP_MARK_DEBUG="1"*/;
 wire                  tx_sysclk       ;
 wire                  tx_rstn         ;

 wire                  rx_sysclk       /* synthesis syn_keep=1 */;
 wire                  rx_rstn         ;
 wire [4*CHAN_N-1:0]   rx_data /* synthesis syn_keep=1 */ ; 
 wire                  sync_done       ;

 assign tx_train_done = rx_train_done;    
 assign err_flag = |err_led ;   

GTP_CLKBUFG u_GTP_CLKBUFG (
    .CLKOUT(ref_clk_r),// OUTPUT  
    .CLKIN(ref_clk)  // INPUT  
);

pgd_rst_debounce #
(
    .DLY1_RST_WIDTH  ( 1 ), //10
    .DLY2_RST_WIDTH  ( 2 )  //11 
)
ext_rst_debounce
(
    .sys_clk    ( ref_clk_r   ),
    .sys_rst_n  ( rstn_in   ),
    .srst_len_n ( rst_n     ) 
);

pgd_clk_rst_gen pgd_clk_rst_gen_inst
(
  .ref_clk     (ref_clk_r    ),
  .rstn_in     (rst_n       ),
  .sysclk      (sysclk      ),
  .rstn_sys    (rstn_sys    ),
  .tx_sysclk   (tx_sysclk   ),
  .tx_rstn     (tx_rstn     ),
  .tx_ioclk    (tx_ioclk    ),
  .tx_gtp_rstn (tx_gtp_rstn )                   
);
   
pgd_ddr_lvds4to1_tx_top #(
   .CHAN_N(CHAN_N),
   .PATTERN(PATTERN)
) pgd_ddr_lvds4to1_tx_top_inst
(
  .tx_sysclk       (tx_sysclk    ),
  .tx_rstn         (tx_rstn      ),
  .tx_ioclk        (tx_ioclk     ),
  .tx_gtp_rstn     (tx_gtp_rstn  ),
  .tx_data         (tx_data      ),
  .tx_data_p       (tx_data_p    ),
  .tx_data_n       (tx_data_n    ),
  .tx_clk_p        (tx_clk_p     ),
  .tx_clk_n        (tx_clk_n     )
);

pgd_ddr_lvds4to1_rx_top #(
   .CHAN_N(CHAN_N),
   .PATTERN(PATTERN)
) pgd_ddr_lvds4to1_rx_top_inst
(   
   .rx_clk_p     (rx_clk_p     ),
   .rx_clk_n     (rx_clk_n     ),
   .sysclk       (sysclk       ),
   .dbg_key_oper (dbg_key_oper ),
   .rstn_sys     (rstn_sys     ),
   .sync_done    (sync_done    ),
   .rx_data_p    (rx_data_p    ),
   .rx_data_n    (rx_data_n    ),
   .rx_sysclk    (rx_sysclk    ),
   .rx_rstn      (rx_rstn      ),
   .rx_data      (rx_data      ),
   .rx_train_done(rx_train_done)
);

wire    [1:0] tx_mode;
assign tx_mode = 2'b10;
pgd_ddr_lvds4to1_test #(
   .CHAN_N(CHAN_N),
   .PATTERN(PATTERN)
) pgd_ddr_lvds4to1_test_inst
(
  .tx_sysclk       (tx_sysclk    ),
  .tx_rstn         (tx_rstn      ), 
  .tx_mode         (tx_mode      ),
  .tx_train_done   (tx_train_done),
  .tx_data         (tx_data      ), 
  .test_trig       (sync_done    ),
  .rx_sysclk       (rx_sysclk    ),
  .rx_rstn         (rx_rstn      ),
  .rx_data         (rx_data      ),
  .rx_train_done   (rx_train_done),
  .err_led         (err_led      )
);




endmodule

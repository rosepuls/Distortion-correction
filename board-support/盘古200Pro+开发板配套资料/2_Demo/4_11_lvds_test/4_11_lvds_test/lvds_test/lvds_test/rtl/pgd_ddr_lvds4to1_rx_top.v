//-----------------------------------------------------------------------------
//Date               : 20200916
//Version           : v1.0
//development board  : PG2L100RD02_A0
//Purpose            : LVDS DEMO
//-----------------------------------------------------------------------------
module pgd_ddr_lvds4to1_rx_top #(
   parameter CHAN_N  = 4,
   parameter PATTERN = 4'b1001
) (  
   input                  sysclk          ,
   input									dbg_key_oper    ,
   input                  rstn_sys        ,   
   input                  rx_clk_p        ,
   input                  rx_clk_n        ,
   
   input  [  CHAN_N-1:0]  rx_data_p       ,
   input  [  CHAN_N-1:0]  rx_data_n       ,
   output                 rx_sysclk       ,
   output                 rx_rstn         ,
   output reg [4*CHAN_N-1:0]  rx_data         ,
   output reg             sync_done           ,
   output                 rx_train_done
);

wire [2:0]  iodly_ctrl      ;
wire [4*CHAN_N-1:0]  rx_data_t       ;
wire                 data_align       /* synthesis syn_keep=1 */;
wire                 start_align     ;
wire          [2:0]  iodly_ctrl_chan ;
wire [4*CHAN_N-1:0]  local            ;
wire [4*CHAN_N-1:0]  data_chan_w     ;
wire [4*CHAN_N-1:0]  rx_data_d    /* synthesis syn_keep=1 */ ;
reg                  sync_trig        ;
reg                  sync_done_s      ;
pgd_ddr_lvds4to1_rxdata #(
   .CHAN_N(CHAN_N)
) pgd_ddr_lvds4to1_rxdata_inst
(
   .sysclk       (sysclk      )   ,
   .dbg_key_oper (dbg_key_oper   )   ,
   .rstn_sys     (rstn_sys    )   ,
   .rx_clk_p     (rx_clk_p    )   ,
   .rx_clk_n     (rx_clk_n    )   , 
   
   .rx_sysclk    (rx_sysclk   )   ,
   .rx_rstn      (rx_rstn     )   ,    
   .rx_data_p    (rx_data_p   )   ,
   .rx_data_n    (rx_data_n   )   ,
   .rx_data_t    (rx_data_t   )   ,   
   .iodly_ctrl   (iodly_ctrl  )     
);

pgd_ddr_lvds4to1_rx_training_ctrl #(
   .CHAN_N(CHAN_N)
)pgd_ddr_lvds4to1_rx_training_ctrl_inst
(
   .rx_sysclk       (rx_sysclk      )   ,
   .rx_rstn         (rx_rstn        )   ,
                                    
   .data_align      (data_align     )   ,
   .start_align     (start_align    )   ,
                    
   .rx_data_t       (rx_data_t      )   ,
   .local           (local          )   ,
   .rx_data         (rx_data_d      )   ,
   .data_chan_w     (data_chan_w    )   ,
   
   .iodly_ctrl_chan (iodly_ctrl_chan)   ,
   .iodly_ctrl      (iodly_ctrl     )   ,
  
   .rx_train_done   (rx_train_done  )                     
   
);

pgd_ddr_lvds4to1_rx_training #(
   .PATTERN(PATTERN)
) pgd_ddr_lvds4to1_rx_training_inst
(
   .rx_sysclk        (rx_sysclk      ),
   .rx_rstn          (rx_rstn        ),

   .data_align_w     (data_align     ),
   .start_align      (start_align    ),  
   .data_chan_w      (data_chan_w    ),

   .local            (local          ),
   .iodly_ctrl_chan  (iodly_ctrl_chan)  
);

//------------------- channel sync ------------------------
always @(posedge rx_sysclk or negedge rx_rstn)
begin
   if (!rx_rstn)
       sync_trig <= 1'b0 ;
   else if ((rx_data_d[3:0]==4'h9)&&(rx_data_d[7:4]==4'h9)&&(rx_data_d[11:8]==4'h9)&&(rx_data_d[15:12]==4'h9))      
       sync_trig <= 1'b1 ;
end

always @(posedge rx_sysclk or negedge rx_rstn)
begin
  if(!rx_rstn)
      rx_data <= 'd0;
  else if(sync_trig)
      rx_data <= rx_data_d;
end

always @(posedge rx_sysclk or negedge rx_rstn)
begin
  if(!rx_rstn)
  begin
    sync_done_s <= 0;
    sync_done   <= 0;
  end else
  begin
    sync_done_s <= sync_trig;
    sync_done   <= sync_done_s;
  end
end 

endmodule
//-----------------------------------------------------------------------------
//Date               : 20200916
//Version           : v1.0
//development board  : PG2L100RD02_A0
//Purpose            : LVDS DEMO
//-----------------------------------------------------------------------------
module pgd_ddr_lvds4to1_test #(
   parameter CHAN_N  = 4 ,
   parameter PATTERN = 4'b1001
) (
  input                      tx_sysclk       ,
  input                      tx_rstn         , 
  input             [1:0]    tx_mode         ,
  input                      tx_train_done   ,
  output reg [4*CHAN_N-1:0]  tx_data         , 
  
  input                      rx_sysclk       ,
  input                      rx_rstn         ,
  input      [4*CHAN_N-1:0]  rx_data         ,
  input                      rx_train_done   ,
  input                      test_trig       ,
  output reg   [CHAN_N-1:0]  err_led         
);
 reg  [3:0]           cnt /*synthesis PAP_MARK_DEBUG="1"*/;
 reg  [3:0]           prbs_data; 
 reg                  tx_en;
 reg  [ 2:0]          tx_cnt  ;
 reg                  tx_prbs_trig  ;
 reg                  tx_prbs_trig1 ;
 reg                  tx_prbs_trig2 ;
 reg  [19:0]          tx_temp_data;
 wire [19:0]          dout_tx_prbs;
 reg  [ 2:0]          rx_cnt;
 reg  [CHAN_N*20-1:0] rx_temp_data;
 reg  [         19:0] dout_rx_prbs[0:CHAN_N-1];
 reg                  rx_en;
 reg                  train_done;
 reg                  train_done0;
 reg  [4*CHAN_N-1:0]  rx_data_d;
 wire [  CHAN_N-1:0]  prbs_err;
 reg                  test;
 reg                  rx_clk_en;
 reg  [3:0]           test_cnt;

parameter  IDLE = 2'd0,
           TRAINING = 2'd1,
           SEND_SYNC_CODE = 2'd2,
           SEND_USER_DATA = 2'd3;
parameter  SYNC_CODE = 4'ha;

 reg  [1:0]  cur_state;
 reg  [1:0]  nxt_state /*synthesis PAP_MARK_DEBUG="1"*/;

//------------transmit data control---------------------
 always @(posedge tx_sysclk or negedge tx_rstn)
     if(!tx_rstn)
     begin
         train_done0 <= 0;
         train_done  <= 0;
     end
     else
     begin
         train_done0 <= tx_train_done;
         train_done  <= train_done0;
     end

always @(posedge tx_sysclk or negedge tx_rstn)
     if(!tx_rstn)
         cur_state <= IDLE;
     else
         cur_state <= nxt_state;

 always @(*)
     case(cur_state)
     IDLE: nxt_state <= TRAINING;
     TRAINING : begin
           if(train_done)
               nxt_state <= SEND_SYNC_CODE;
           else
               nxt_state <= TRAINING;
           end
     SEND_SYNC_CODE: nxt_state <= SEND_USER_DATA;
     SEND_USER_DATA: nxt_state <= SEND_USER_DATA;

     default: nxt_state <= IDLE;
     endcase

 always @(posedge tx_sysclk or negedge tx_rstn)
     if(!tx_rstn)
             tx_data <= {(4*CHAN_N){1'b0}}  ;
     else
         case(nxt_state)
         IDLE: tx_data <= {(4*CHAN_N){1'b0}}  ;
         TRAINING: tx_data <= {CHAN_N{PATTERN}}     ;
         SEND_SYNC_CODE: tx_data <= {CHAN_N{SYNC_CODE}}     ;
         SEND_USER_DATA:begin
                        case(tx_mode)
                        2'd0: tx_data <= {(CHAN_N){PATTERN}};
                        2'd1: tx_data <= {(CHAN_N){4'ha}};
                        2'd2: tx_data <= {(CHAN_N){cnt}} ;
                        2'd3: tx_data <= {(CHAN_N){prbs_data}} ;
                        default:  ; 
                        endcase
                        end
         endcase
 
 always @(posedge tx_sysclk or negedge tx_rstn)
     if(!tx_rstn)
         cnt <= 4'd0;
     else 
         cnt <= cnt + 1'd1;

 always @(posedge tx_sysclk or negedge tx_rstn)
    if(!tx_rstn)
        tx_cnt <= 3'd0;
    else if(tx_cnt == 3'd5)
        tx_cnt <= 3'd1;
    else
        tx_cnt <= tx_cnt+3'd1;   

 always @(posedge tx_sysclk or negedge tx_rstn)
    if(!tx_rstn)
    begin
        tx_prbs_trig <= 1'b0;
        tx_en        <= 1'b0;
    end
    else if(tx_cnt == 3'd3)
    begin
        tx_prbs_trig <= 1'b1;
        tx_en        <= 1'b1;
    end
    else
        tx_en        <= 1'b0;
 
 always @(posedge tx_sysclk or negedge tx_rstn)
    if(!tx_rstn)
    begin
        tx_prbs_trig1 <= 1'b0;      
        tx_prbs_trig2 <= 1'b0; 
    end
    else
    begin
        tx_prbs_trig1 <= tx_prbs_trig;      
        tx_prbs_trig2 <= tx_prbs_trig1; 
    end

 always @(posedge tx_sysclk or negedge tx_rstn)
    if(!tx_rstn)
        tx_temp_data <= 20'd0;
    else
        tx_temp_data <= dout_tx_prbs;


always @(posedge tx_sysclk or negedge tx_rstn)
    if(!tx_rstn)
        prbs_data <= 4'd0;
    else if(tx_prbs_trig2 == 1'b1)  
    begin
        case(tx_cnt)
        3'd1 :prbs_data <= tx_temp_data[3: 0];
        3'd2 :prbs_data <= tx_temp_data[7: 4];
        3'd3 :prbs_data <= tx_temp_data[11:8];
        3'd4 :prbs_data <= tx_temp_data[15:12];
        3'd5 :prbs_data <= tx_temp_data[19:16];                    
        default:prbs_data<=prbs_data;
        endcase
    end 

prbs_gen 
#(
.PRBS_GEN_EN    (1)
)prbs_txdata_gen
(
        .clk                 ( tx_sysclk       ),
        .rstn                ( tx_rstn         ),
        .clk_en              ( tx_en           ),
        .cfg_prbs_mode       ( 4'h4            ),
        .cfg_insert_er       ( 1'b0            ),
        .din                 ( 20'b0           ),
        .dout                ( dout_tx_prbs    ),
        .cfg_error_cnt_clr   ( 1'b1            ),
        .error               (     ),
        .error_cnt           (     )
);    
//--------------------receive data and test------------------------   
always @(posedge rx_sysclk or negedge rx_rstn)
    if(!rx_rstn)  
        test_cnt <= 4'd0;
    else if(test)
    begin
        if(test_cnt==4'd13)
             test_cnt <= test_cnt;
        else
             test_cnt <= test_cnt+1;
    end
    else
        test_cnt <= 4'd0;


always @(posedge rx_sysclk or negedge rx_rstn)
    if(!rx_rstn)  
        rx_cnt <= 3'd0;
     else if(test_trig)
     begin
        if(rx_cnt == 3'd5)
            rx_cnt <= 3'd1;
        else
            rx_cnt <= rx_cnt+3'd1;
     end
     else
         rx_cnt <= 3'd0;
        
always @(posedge rx_sysclk or negedge rx_rstn)
    if(!rx_rstn) 
        rx_en <= 1'b0;
    else if(rx_cnt==3'd5)
        rx_en <= 1'b1;
    else
        rx_en <= 1'b0;

always @(posedge rx_sysclk or negedge rx_rstn)
    if(!rx_rstn) 
        rx_clk_en <= 1'b0;
    else
        rx_clk_en <= rx_en;

always @(posedge rx_sysclk or negedge rx_rstn)
    if(!rx_rstn) 
    begin
        test  <= 0;
    end
    else
    begin
        test  <= test_trig;
    end
 

 genvar i;
 generate 
 for(i=0;i<CHAN_N;i=i+1) begin: rxdata_delay
 
 always @(posedge rx_sysclk or negedge rx_rstn)
    if(!rx_rstn)
        rx_data_d[4*i+3:4*i]  <= 4'h0;
    else
        rx_data_d[4*i+3:4*i]  <= rx_data[4*i+3:4*i];
 
 always @(posedge rx_sysclk or negedge rx_rstn)
    if(!rx_rstn)       
        err_led[i] <= 1'b0;
    else if(test_cnt==4'd13)
    begin
        case(tx_mode)
        2'b00:begin if(rx_data[4*i+3:4*i] != PATTERN) err_led[i] <= 1'b1;  else err_led[i] <= 0; end             
        2'b01:begin if(rx_data[4*i+3:4*i] != 4'ha) err_led[i] <= 1'b1; else err_led[i] <= 0; end
        2'b10:begin if(rx_data[4*i+3:4*i] != rx_data_d[4*i+3:4*i]+4'h1) err_led[i] <= 1'b1; else err_led[i] <= 0; end
        2'b11:begin  err_led[i] <= prbs_err[i] ;end
        default:  err_led[i] <= 1'b0;
        endcase
    end 

always @(posedge rx_sysclk or negedge rx_rstn)
    if(!rx_rstn)
        rx_temp_data[20*i+19:20*i] <= 20'd0;
    else if(test)
    begin
        case(rx_cnt)
        3'd1 :rx_temp_data[20*i+3:20*i] <= rx_data_d[4*i+3:4*i];
        3'd2 :rx_temp_data[20*i+7:20*i+4] <= rx_data_d[4*i+3:4*i];
        3'd3 :rx_temp_data[20*i+11:20*i+8] <= rx_data_d[4*i+3:4*i];
        3'd4 :rx_temp_data[20*i+15:20*i+12] <= rx_data_d[4*i+3:4*i];
        3'd5 :rx_temp_data[20*i+19:20*i+16] <= rx_data_d[4*i+3:4*i];                    
        default:rx_temp_data[20*i+19:20*i]<=rx_temp_data[20*i+19:20*i];
        endcase
    end                
  
   always @(posedge rx_sysclk or negedge rx_rstn)
      if(!rx_rstn)
          dout_rx_prbs[i] <= 20'd0;
      else if(rx_en)
          dout_rx_prbs[i] <= rx_temp_data[20*i+19:20*i];
      else  
          dout_rx_prbs[i] <= dout_rx_prbs[i];
      
   prbs_gen #(                                                   
    .PRBS_GEN_EN    (0)                                  
   )prbs_rxdata_gen                                       
  (                                                    
        .clk                 ( rx_sysclk      ), 
        .rstn                ( rx_rstn        ), 
        .clk_en              ( rx_clk_en      ), 
        .cfg_prbs_mode       ( 4'h4           ), 
        .cfg_insert_er       ( 1'b0           ), 
        .din                 ( dout_rx_prbs[i]), 
        .dout                (                ), 
        .cfg_error_cnt_clr   ( 1'b1           ), 
        .error               ( prbs_err[i]    ), 
        .error_cnt           (                )  
   );   
    
  end
  endgenerate
 

             
endmodule
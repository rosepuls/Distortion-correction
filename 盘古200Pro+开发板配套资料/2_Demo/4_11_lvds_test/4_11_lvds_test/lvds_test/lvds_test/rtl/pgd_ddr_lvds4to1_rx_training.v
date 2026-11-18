//-----------------------------------------------------------------------------
//Date               : 20200916
//Version           : v1.0
//development board  : PG2L100RD02_A0
//Purpose            : LVDS DEMO
//-----------------------------------------------------------------------------
module pgd_ddr_lvds4to1_rx_training #(
   parameter CHAN_N  = 4 ,
   parameter PATTERN = 4'b1001
) (
   input                  rx_sysclk       ,
   input                  rx_rstn         ,
   
   output                 data_align_w ,
   input                  start_align     ,  
   input  [4*CHAN_N-1:0]  data_chan_w ,
   
   output     reg [2:0]   iodly_ctrl_chan , 
   output     reg [4*CHAN_N-1:0]   local        
);
//localparam CNT_MAX    =20'hfffff;
localparam CNT_MAX    =12'hfff;
localparam DELAY_TIME = 8'd200;

parameter IDLE        = 3'd0,
          SAMP_DATA   = 3'd1,
          TRAIN_END   = 3'd2,
          CORRECT     = 3'd3,
          DELAY       = 3'd4,
          WORDALIGN   = 3'd5;
                   
reg [ 2:0]  curr_state /*synthesis PAP_MARK_DEBUG="1"*/;
reg [ 2:0]  next_state ; 
reg [11:0]  samp_cnt   ;
reg [4*CHAN_N-1:0]  data_chan_d; 
reg [ 7:0]  local_cnt  ;  
reg         bitslip_ok ;  
reg         phase_adj  ;
reg [ 6:0]  phase_cnt  ;
reg         data_comp_en ;
wire         err;
reg [ 7:0]  delay_cnt ;
reg         wordalign_start;
reg         state_vld     ;
reg         metastate     ;
reg [ 6:0]  state_loc     ;
reg         samp_end      ;
reg  [CHAN_N-1 :0]       retrain       ;
reg  [CHAN_N-1 :0]       data_align    ;
reg  [CHAN_N-1 :0]       err_ch        ;
wire[ 3:0]  pattern_temp  ;  
wire        boundary_end  /* synthesis syn_keep=1 */;
wire        retrain_w ;
wire  [6:0] right_step    ;

assign pattern_temp = PATTERN;

always @(posedge rx_sysclk or negedge rx_rstn)
	  if(!rx_rstn)
	       curr_state <= 3'b0;
	  else 
         curr_state <= next_state; 

// fsm train_req
always @( * )
begin
     case(curr_state)
     IDLE: begin
               if(start_align)
                   next_state <= SAMP_DATA;
               else
                   next_state <= IDLE;
           end                          
     SAMP_DATA: begin
                    if(samp_end == 1'b1)
                        next_state <= TRAIN_END;
                    else
                        next_state <= SAMP_DATA;
                end 
     TRAIN_END: begin
                    if(boundary_end == 1'b1)
                        next_state <= CORRECT;
                    else
                        next_state <= SAMP_DATA;                   
                end 
     CORRECT : begin
                   if(bitslip_ok == 1'b1)
                       next_state <= DELAY; 
                   else
                       next_state <= CORRECT; 
               end 
     DELAY   : begin
                   if(wordalign_start == 1'b1)
                       next_state <= WORDALIGN; 
                   else
                       next_state <= DELAY;  
               end
     WORDALIGN:begin
                   if(data_align_w)
                       next_state <= IDLE;  
                   else
                       next_state <= SAMP_DATA;
               end
    default :  next_state <= IDLE;
    endcase                     
end

always @(posedge rx_sysclk or negedge rx_rstn)
	  if(!rx_rstn)
	      samp_cnt <= 12'b0;
	  else if(curr_state == SAMP_DATA) 
	  begin 
	      if(samp_cnt == CNT_MAX)
	          samp_cnt <= 12'b0;
	      else
	          samp_cnt <= samp_cnt + 12'b1;
	  end
	  else
	     samp_cnt <= 12'b0;      

// phase_adj gen
always @(posedge rx_sysclk or negedge rx_rstn)
	  if(!rx_rstn)
	      phase_adj <= 1'b0;
//	  else if(samp_cnt == 20'hffffe)
	  else if(samp_cnt == 12'hffe)
	      phase_adj <= 1'b1;
	  else
	      phase_adj <= 1'b0; 

//phase_adj cnt
always @(posedge rx_sysclk or negedge rx_rstn)
	  if(!rx_rstn)
	      phase_cnt <= 7'd0;	  
	  else if(curr_state == WORDALIGN)
	      phase_cnt <= 7'd0;
	  else if(phase_adj)
	      phase_cnt <= phase_cnt + 7'd1;
	      
// data_compare valid 
always @(posedge rx_sysclk or negedge rx_rstn)
	  if(!rx_rstn)
	      data_comp_en <= 1'b0;
//	  else if(samp_cnt>=20'h0001f && samp_cnt<= 20'hffff0)
	  else if(samp_cnt>=12'h01f && samp_cnt<= 12'hff0)	  
        data_comp_en <=1'b1;
      else
        data_comp_en <=1'b0; 	

//-----------err_check-------------------------------------------------
genvar i;
generate 
for(i=0;i<CHAN_N;i=i+1) begin : err_check

always @(posedge rx_sysclk or negedge rx_rstn)
begin
	  if(!rx_rstn)
	    data_chan_d[4*i+3:4*i] <= 4'd0;
	  else  
        data_chan_d[4*i+3:4*i] <= data_chan_w[4*i+3:4*i];
end

always @(posedge rx_sysclk or negedge rx_rstn)
begin
	  if(!rx_rstn)
	      err_ch[i] <= 1'b0;	 
	  else if(data_comp_en)
	     begin 
         if((data_chan_w[4*i+3:4*i] != data_chan_d[4*i+3:4*i])||((data_chan_w[4*i+3:4*i]!=4'h9)&&(data_chan_w[4*i+3:4*i]!=4'h3)&&(data_chan_w[4*i+3:4*i]!=4'h6)&&(data_chan_w[4*i+3:4*i]!=4'hc)))
            err_ch[i] <= 1'b1;
         end
      else
       err_ch[i] <= 1'b0; 	
end
end
endgenerate

assign err = |err_ch ;

always @(posedge rx_sysclk or negedge rx_rstn)
	  if(!rx_rstn)
	  begin
	     state_vld <= 1'b0;
         metastate <= 1'b0;
         state_loc <= 7'b0;
	  end
//  else if(samp_cnt == 20'hffff2)
	  else if(samp_cnt == 12'hff2)
	  begin 
	      state_vld <= 1'b1;
          metastate <= err;
          state_loc <= phase_cnt; 
     end
     else
     begin
          state_vld <= 1'b0;
          metastate <= 1'b0;
          state_loc <= 7'b0;
     end

//samp_data
always @(posedge rx_sysclk or negedge rx_rstn)
	  if(!rx_rstn)
	      samp_end  <= 1'b0;
//	  else if(samp_cnt == 20'hffffe)
	  else if(samp_cnt == 12'hffe)
	      samp_end  <= 1'b1;
    else
        samp_end  <= 1'b0;

always @(posedge rx_sysclk or negedge rx_rstn)
	  if(!rx_rstn)
	       local_cnt <= 8'd0;
	  else if(curr_state == CORRECT)
	  begin
	       if(local_cnt[7:1] >= right_step[6:0])
	           local_cnt <= local_cnt;
	       else 
	           local_cnt <= local_cnt+ 8'd1; 
	  end
	  else
	      local_cnt <= 8'd0;
 
always @(posedge rx_sysclk or negedge rx_rstn)
	  if(!rx_rstn)
	      bitslip_ok <= 1'b0;
	  else if(bitslip_ok == 1'b1)
	      bitslip_ok <= 1'b0; 
	  else if(curr_state == CORRECT) 
	  begin
	      if(local_cnt[7:1] >= right_step[6:0])
	          bitslip_ok <= 1'b1;
	      else
	          bitslip_ok <= 1'b0;	
	  end	             

// ----------------- iodelay control  ----------------------------------------------   
always @(posedge rx_sysclk or negedge rx_rstn)   // load : high invalid
	  if(!rx_rstn)
	      iodly_ctrl_chan[2] <= 1'b0;
	  else if(curr_state == IDLE) 
	      iodly_ctrl_chan[2] <= 1'b1;
	  else if((curr_state ==TRAIN_END)&&(next_state == CORRECT))
	      iodly_ctrl_chan[2] <= 1'b1;
	  else if((curr_state == SAMP_DATA)||(curr_state ==CORRECT))
	      iodly_ctrl_chan[2] <= 1'b0;	       

always @(posedge rx_sysclk or negedge rx_rstn)  // move : add or decrease step
	  if(!rx_rstn)
	      iodly_ctrl_chan[1] <= 1'b0;
	  else if(curr_state == CORRECT)
	      iodly_ctrl_chan[1] <= ~iodly_ctrl_chan[1];
	  else
	      iodly_ctrl_chan[1] <= ~ phase_adj;

always @(posedge rx_sysclk or negedge rx_rstn)  // direction : dynamic aligment
	  if(!rx_rstn)
	      iodly_ctrl_chan[0] <= 1'b0;
	  else 
	      iodly_ctrl_chan[0] <= 1'b0;  

//------------------------------------------------------------------------------------
always @(posedge rx_sysclk or negedge rx_rstn)
	  if(!rx_rstn)
	      delay_cnt <= 8'd0;
	  else if(curr_state == DELAY)
	      delay_cnt <= delay_cnt + 8'd1;   
	  else
	      delay_cnt <= 8'd0; 

always @(posedge rx_sysclk or negedge rx_rstn)
	  if(!rx_rstn)
	      wordalign_start <= 1'b0;
	  else if(wordalign_start == 1'b1)	
	      wordalign_start <= 1'b0;  
	  else if(delay_cnt == DELAY_TIME)
	      wordalign_start <= 1'b1;
	  else 
	      wordalign_start <= 1'b0; 

//------------------------------------------------	      	      
//----- word_align ------
genvar k;
generate 
for(k=0;k<CHAN_N;k=k+1) begin : rxdata
always @(posedge rx_sysclk or negedge rx_rstn)
	  if(!rx_rstn)begin 
          data_align[k]    <= 1'b0 ;
	      local[4*k+3:4*k] <= 4'd0 ;
          retrain[k]       <= 1'b0 ;
     end
	  else if(wordalign_start== 1'b1)
	  begin	     
	      case(data_chan_w[4*k+3:4*k])
	       pattern_temp                        :   begin data_align[k] <= 1'b1 ; local[4*k+3:4*k]<= 4'd0   ; retrain[k] <= 1'b0 ;end
	      {pattern_temp[2:0],pattern_temp[3  ]}:   begin data_align[k] <= 1'b1 ; local[4*k+3:4*k]<= 4'd1   ; retrain[k] <= 1'b0 ;end
	      {pattern_temp[1:0],pattern_temp[3:2]}:   begin data_align[k] <= 1'b1 ; local[4*k+3:4*k]<= 4'd2   ; retrain[k] <= 1'b0 ;end  
	      {pattern_temp[0:0],pattern_temp[3:1]}:   begin data_align[k] <= 1'b1 ; local[4*k+3:4*k]<= 4'd3   ; retrain[k] <= 1'b0 ;end 
	      default: begin data_align[k] <= 1'b0 ; local[4*k+3:4*k]<= 4'd4   ; retrain[k] <= 1'b1 ;end  
	      endcase
	  end
end
endgenerate

assign data_align_w = data_align[0]& data_align[1]&data_align[2]&data_align[3];
assign retrain_w = |retrain ;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	    
pgd_sample_ctrl pgd_sample_ctrl_inst
(
	.clk         (rx_sysclk   ),
	.rstn        (rx_rstn     ),
	.state_vld   (state_vld   ),
	.metastate   (metastate   ),
	.state_loc   (state_loc   ),
	.clr         (retrain_w   ),
	.boundary_end(boundary_end),
	.right_step  (right_step  )
); 	            
        		      
endmodule
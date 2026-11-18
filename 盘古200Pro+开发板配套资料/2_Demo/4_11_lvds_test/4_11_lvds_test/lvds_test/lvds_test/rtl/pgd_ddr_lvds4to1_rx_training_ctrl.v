//-----------------------------------------------------------------------------
//Date               : 20200916
//Version           : v1.0
//development board  : PG2L100RD02_A0
//Purpose            : LVDS DEMO
//-----------------------------------------------------------------------------
module pgd_ddr_lvds4to1_rx_training_ctrl #(
   parameter CHAN_N  = 4
) (
   input                       rx_sysclk       ,
   input                       rx_rstn         ,
   
   input                       data_align      ,
   output reg                  start_align     ,
   
   input      [4*CHAN_N-1:0]   rx_data_t       ,
   input      [4*CHAN_N-1:0]   local            ,
   output reg [4*CHAN_N-1:0]   rx_data         ,
   
   input               [2:0]   iodly_ctrl_chan ,
   output reg          [2:0]   iodly_ctrl      ,
   output reg [4*CHAN_N-1:0]   data_chan_w ,
   
   output reg                  rx_train_done                        
   
);

 reg           [7:0]   cnt          ;
 reg           [3:0]   chan_cnt     ;   
 reg           [4*CHAN_N-1:0]   rx_data_d0  ;
 reg           [4*CHAN_N-1:0]   rx_data_d1  ;
 reg           [3:0]   iodly_ctrl_mem ;
 reg           [4*CHAN_N-1:0]   local_mem /* synthesis syn_preserve = 1 */;
                 
 always @(posedge rx_sysclk or negedge rx_rstn)
     if(!rx_rstn)
         cnt <= 8'h0;
     else if(~rx_train_done)
     begin
         if(data_align)
             cnt <= 8'h0; 
         else if(cnt == 8'hff)
             cnt <= cnt ;
         else
             cnt <= cnt + 8'h01;
     end
     else
         cnt <= 8'h0;
  
 always @(posedge rx_sysclk or negedge rx_rstn)
     if(!rx_rstn)
         start_align <= 1'b0;
     else if(cnt == 8'hfe)
         start_align <= 1'b1;
     else
         start_align <= 1'b0;     

 always @(posedge rx_sysclk or negedge rx_rstn)
     if(!rx_rstn)
         rx_train_done <= 1'b0;
     else if(data_align )
         rx_train_done <= 1'b1; 

////////////////////////////////////////////////////////////////////////////
wire [4*CHAN_N-1:0] data_mem_w ;
assign data_mem_w = rx_data_t;
always @(posedge rx_sysclk or negedge rx_rstn)
     if(!rx_rstn) 
         data_chan_w <= 'd0;
     else             
         data_chan_w  <=  data_mem_w ;

/////////////////////////////////////////////////////////////////////////////
 always @(posedge rx_sysclk or negedge rx_rstn)
     if(!rx_rstn) 
     begin
         rx_data_d0  <= {CHAN_N{4'h00}};
         rx_data_d1  <= {CHAN_N{4'h00}};
     end
     else
     begin             
         rx_data_d0  <= rx_data_t;
         rx_data_d1  <= rx_data_d0;
     end
          
 always @(posedge rx_sysclk or negedge rx_rstn)
    begin
        if(!rx_rstn)
            iodly_ctrl <= 3'b0;  
        else if(~rx_train_done)
            iodly_ctrl <= iodly_ctrl_chan; 
        else 
            iodly_ctrl <= iodly_ctrl;
    end

//-------------------- wordalign --------------------  
 genvar m;
 generate 
 for(m=0;m<CHAN_N;m=m+1) begin : local_story       
 always @(posedge rx_sysclk or negedge rx_rstn)
 begin
     if(!rx_rstn)
         local_mem[4*m+3:4*m] <= 4'h0;
     else if(data_align)
         local_mem[4*m+3:4*m] <= local[4*m+3:4*m];
 end
 end
 endgenerate
          
 genvar k;
 generate 
 for(k=0;k<CHAN_N;k=k+1) begin : rxdata
    always @(posedge rx_sysclk)
    begin
        case(local_mem[4*k+3:4*k])
             4'd0  : rx_data[4*k+3:4*k] <=  rx_data_d1[4*k+3 :4*k]      ;
	         4'd1  : rx_data[4*k+3:4*k] <= {rx_data_d0[       4*k],rx_data_d1[4*k+3:4*k+1]};
	         4'd2  : rx_data[4*k+3:4*k] <= {rx_data_d0[4*k+1 :4*k],rx_data_d1[4*k+3:4*k+2]};
	         4'd3  : rx_data[4*k+3:4*k] <= {rx_data_d0[4*k+2 :4*k],rx_data_d1[4*k+3:4*k+3]};
	         default: rx_data[4*k+3:4*k] <= 4'd0 ;
	     endcase        
    end
 end
 endgenerate

   
endmodule
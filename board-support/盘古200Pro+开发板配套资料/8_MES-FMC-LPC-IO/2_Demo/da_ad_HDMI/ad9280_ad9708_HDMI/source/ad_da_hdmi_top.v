module ad_da_hdmi_top(
   input    wire  clk_27M           ,
   input    wire  rst_n             ,
   output   wire  rstn_out          ,
   //HDMI config
   output   wire  iic_tx_scl        ,
   inout    wire  iic_tx_sda        ,
   output   wire  led_int           ,
   //ADDA
   input    wire  [7:0]ad_data_in   ,
   output   wire  ad_clk            ,
   output   wire  da_clk            ,
   output   wire  [7:0]da_data_out  , 
   output   wire        vout_hs     ,            
   output   wire        vout_vs     ,            
   output   wire        vout_de     ,            
   output   wire        vout_clk    ,           
   output   wire  [23:0]vout_data           
   );

//wire clk_125M ;
wire lock ;
wire pll_lock ;
wire clk_118_8 ;
wire clk_29_7 ;

wire pix_clk ;
wire [7:0]  hdmi_r_out ; 
wire [7:0]  hdmi_g_out ; 
wire [7:0]  hdmi_b_out ;
wire hdmi_vs_out ;
wire hdmi_hs_out ;
wire hdmi_de_out ;

wire [23:0]  grid_data_out ;
wire grid_vs_out ;
wire grid_hs_out ;
wire grid_de_out ;

assign vout_clk = pix_clk ;
//pll_clock_125m u_pll (
//  .clkin1(clk_50M),        // input    // 50Mhz
//  .pll_lock(lock),         // output   
//  .clkout0(clk_125M)       // output   
//);

pll_adda u_pll_adda (
  .clkin1(clk_27M),         // input
  .lock(pll_lock),      // output
  .clkout0(clk_118_8),      // output   //118.8Mhz
  .clkout1(clk_29_7)        // output   //29.7Mhz
);

assign ad_clk = clk_29_7 ;

//output color bar
hdmi_test  hdmi_color(
   .sys_clk      (clk_27M   ) ,// input system clock 50MHz    
   .rstn_out     (rstn_out  ) ,
   .iic_tx_scl   (iic_tx_scl) ,
   .iic_tx_sda   (iic_tx_sda) ,
   .led_int      (led_int   ) ,
   .pix_clk      (pix_clk   ) ,//pixclk                           
   .vs_out       (hdmi_vs_out    ) , 
   .hs_out       (hdmi_hs_out    ) , 
   .de_out       (hdmi_de_out    ) ,
   .r_out        (hdmi_r_out     ) , 
   .g_out        (hdmi_g_out     ) , 
   .b_out        (hdmi_b_out     ) 
);

//output grid
grid_display grid_display_1(
	.rst_n      (rst_n      ) ,                              
	.pclk       (pix_clk    ) ,                          
	.i_hs       (hdmi_hs_out) ,                            
	.i_vs       (hdmi_vs_out) ,                           
	.i_de       (hdmi_de_out) ,                          
	.i_data     ({hdmi_r_out[7:0] , hdmi_g_out[7:0] , hdmi_b_out[7:0]}) ,                            
	.o_hs       (grid_hs_out) ,                          
	.o_vs       (grid_vs_out) ,                          
	.o_de       (grid_de_out) ,                          
	.o_data     (grid_data_out)                             
);

//output hdmi wave
wav_display wav_display_1(
	.rst_n         (rst_n        ) ,                                      
	.pclk          (pix_clk      ) ,                         
	.wave_color    (24'hff0000) ,                              
   .ad_clk        (ad_clk    ) ,                           
	.ad_data_in    (ad_data_in) ,                              
	.i_hs          (grid_hs_out   ) ,                        
	.i_vs          (grid_vs_out   ) ,                        
	.i_de          (grid_de_out   ) ,                        
	.i_data        (grid_data_out ) ,                          
	.o_hs          (vout_hs      ) ,                        
	.o_vs          (vout_vs      ) ,                        
	.o_de          (vout_de      ) ,                        
	.o_data        (vout_data    )                          
);


//output wave

ad9708_sin_wave  a_sin_wave  (
   .clk           (clk_118_8) ,   
   .rst_n         (rst_n)    , 
   .da_clk        (da_clk)   ,
   .da_data       (da_data_out)  //  116Khz sine wave
   );


endmodule
module video_sfp_top(

    input           clk_in1,//27MH    input           clk_in2,//50MHz
    input           pix_clk_in,
    input           rstn,
    input   [23:0]  hdmi_data_in,
    input           hs_in,
    input           vs_in,
    input           de_in,
    input           key_rstn,
    input           rx_rstn,
    
    output          pix_clk_out,
    output  [23:0]  hdmi_data_out,
    output          hs_out,
    output          vs_out,
    output          de_out,


    output          iic_scl,
    inout           iic_sda,
    output          rstn_out,

    input           i_p_refckn_1,
    input           i_p_refckp_1,

    input           i_p_l1rxn,
    input           i_p_l1rxp,

    output          o_p_l1txn,
    output          o_p_l1txp,

    output  [1:0]   sfp_disable,
    output          led,
    output          o_rxlane_done_1
   );
assign yuv_out=8'hff;
assign sfp_disable=2'b0; 
wire  [15:0]  data_in_565;
wire  [15:0]  data_out_565;
assign data_in_565={hdmi_data_in[23:19],hdmi_data_in[15:10],hdmi_data_in[7:3]};
assign hdmi_data_out={data_out_565[15:11],3'b111,data_out_565[10:5],2'b11,data_out_565[4:0],3'b111};


//wire rstn;
wire cfg_clk;
wire locked;
wire [31:0]gt_tx_data;
wire [3:0]gt_tx_ctrl;
wire [31:0]o_rxd_1;
wire [3:0]o_rxk_1;
wire clkout0;
wire lock;
wire rstn_cfg;
wire init_over;
cfg_pll cfg_pll (
  .clkout0(clkout0),    // output
  .lock(lock),          // output
  .clkin1(clk_in1)       // input
);
//wire o_txlane_done_1/*synthesis PAP_MARK_DEBUG="1"*/;
wire o_txlane_done_1/*synthesis PAP_MARK_DEBUG="1"*/;
    reg [15:0]rstn_2ms;
 
    ms72xx_ctl ms72xx_ctl(
        .clk             (  clkout0        ), //input       clk,
        .rst_n           (  rstn_cfg       ), //input       rstn,
        .init_over       (  init_over   ), //output      init_over,                                

        .iic_scl         (  iic_scl        ), //output      iic_scl,
        .iic_sda         (  iic_sda        )  //inout       iic_sda
    );
reg init_over_1d;
reg init_over_flag;
reg init_over_flag_1d;
reg [31:0]init_over_cnt;
always @(posedge clkout0)
begin
    if(!rstn)
       init_over_cnt <= 32'b0;
     else if(init_over_flag && init_over_cnt<32'd8000000)
       init_over_cnt <= init_over_cnt + 1'b1;
    else
       init_over_cnt <= init_over_cnt;
end
always @(posedge clkout0)
begin
    if(!rstn)
       init_over_flag <= 1'b0;
     else if(!init_over_1d && init_over)
       init_over_flag <= 1'b1;
    else
       init_over_flag <= init_over_flag;
end
always @(posedge clkout0)
begin
    init_over_1d <= init_over;
    init_over_flag_1d <= init_over_flag;
end
    always @(posedge clkout0)
    begin
        if(!lock || (init_over_cnt>32'd7999900 && init_over_cnt<32'd8000000))
            rstn_2ms <= 16'd0;
        else if(rstn_2ms < 16'd2710)
            rstn_2ms <= rstn_2ms + 1'b1;
        else
            rstn_2ms <= rstn_2ms;
    end
    
    assign rstn_out = (rstn_2ms == 16'd2710);//2ms
   assign rstn_cfg=rstn_out;
assign led=init_over;
wire tx1_clk;
 
    send_encode send_encode
        (
        .tx_clk     (tx1_clk),        // input
        .rstn       (rstn),              // input
        .pix_clk    (pix_clk_in),        // input
        .hs_in      (hs_in),            // input
        .vs_in      (vs_in),            // input
        .de_in      (de_in),                  // input
        .video_data_in   (data_in_565),      // input
        .txd (gt_tx_data),  // output
        .txk (gt_tx_ctrl)   // output
    );  

//assign led=| gt_tx_data;
wire vs_frame;
wire de;
wire [31:0]rx_data_align;
wire [3:0]rx_ctrl_align;
wire [15:0]vout_data;
wire rx1_clk;
//wire [15:0]de_out;
    rec_decode rec_decode
        (
        .rstn       (rstn ),                  // input
        .rx_clk     (rx1_clk),            // input
        .pix_clk(pix_clk_in),
        .rxd (rx_data_align),    // input
        .rxk (rx_ctrl_align),    // input
        .de_sync_vg         (de ),                    // output
        .vs_sfp_rx         (vs_frame),                    // output
        .vout_data_o  (vout_data)       // output
    ); 
assign  data_out_565=vout_data;
   sync_vg sync_vg
    (
    .clk(pix_clk_in),          // input
    .rstn(rstn),        // input
    .vs_frame(vs_frame),
    .vs_out_2d(vs_out),    // output
    .hs_out_2d(hs_out),    // output
    .de_out_2d(de_out),
    .de_out_1d(de),    // output
    .x_act(x_act),      // output
    .y_act(y_act),      // output
    .f_end(f_end)       // output
);
assign pix_clk_out=pix_clk_in;
    word_align word_align
        (
        .rstn           (rstn   ),                      // input
        .rx_clk         (rx1_clk),                // input
        .rx_data     (o_rxd_1),        // input
        .rx_ctrl     (o_rxk_1),        // input
        .rx_data_align  (rx_data_align),  // output
        .rx_ctrl_align  (rx_ctrl_align)   // output
    );
wire i_wtchdg_clr_0;

wire o_pll_done_0/*synthesis PAP_MARK_DEBUG="1"*/;
//assign rstn=1'b1;
hsst_test_dut_top hsst_test_dut_top
    (
    .i_free_clk(clk_in1),                    // input
    .rst_n(rstn),
//    .i_pll_rst_0(!key_rstn),                  // input
//    .i_wtchdg_clr_0(1'b0),            // input
    .o_wtchdg_st_0(o_wtchdg_st_0),              // output
    .o_pll_done_0(o_pll_done_0),                // output
    .o_txlane_done_1(o_txlane_done_1),          // output
    .o_rxlane_done_1(o_rxlane_done_1),          // output
    .i_p_refckn_1(i_p_refckn_1),                // input
    .i_p_refckp_1(i_p_refckp_1),                // input
    .o_p_pll_lock_0(o_p_pll_lock_0),            // output
    .o_p_rx_sigdet_sta_1(o_p_rx_sigdet_sta_1),  // output
    .o_p_lx_cdr_align_1(o_p_lx_cdr_align_1),    // output
    .i_p_l1rxn(i_p_l1rxn),                      // input
    .i_p_l1rxp(i_p_l1rxp),                      // input
    .o_p_l1txn(o_p_l1txn),                      // output
    .o_p_l1txp(o_p_l1txp),                      // output
    .o_rxstatus_1(o_rxstatus_1),                // output
    .o_rdisper_1(o_rdisper_1),                  // output
    .o_rdecer_1(o_rdecer_1),                    // output
//    .src_rst(!key_rstn),                          // input
//    .chk_rst(!key_rstn),                          // input
    .o_pl_err(o_pl_err),                        // output[3:0]
    .tx1_clk(tx1_clk),                          // output
    .txd_1(gt_tx_data),                              // input[31:0]
    .txk_1(gt_tx_ctrl),                              // input[3:0]
    .rx1_clk(rx1_clk),                          // output
    .rxd_1(o_rxd_1),                              // output[31:0]
    .rxk_1(o_rxk_1)                               // output[3:0]
);

endmodule
module tb_hdmi(

   );

reg clk_in1=0;
reg pix_clk_in=0;
reg rstn=0;
wire i_p_refckn_0;
wire i_p_refckp_0;
initial begin
pix_clk_in = 0;
rstn = 0;
clk_in1=0;
#200;
rstn = 1;

end
always #(10)  pix_clk_in = ~pix_clk_in;
always #(20)  clk_in1 = ~clk_in1;
assign i_p_refckn_0=pix_clk_in;
assign i_p_refckp_0=~pix_clk_in;
wire vs_out_2d;
wire hs_out_2d;
wire de_out_2d;
wire [16:0]yuv_data;
wire o_txlane_done_1;

sync_vg_test sync_vg_test
    (
    .clk(pix_clk_in),              // input
    .rstn(o_rxlane_done_1),            // input
    .vs_out_2d(vs_out_2d),  // output
    .hs_out_2d(hs_out_2d),  // output
//    .de_out(de_out),        // output
    .de_out_2d(de_out_2d),  // output
//    .x_act(x_act),          // output[11:0]
//    .y_act(y_act),          // output[11:0]
//    .f_end(f_end) ,          // output
    .yuv_data(yuv_data)
);


GTP_GRS GRS_INST(
		.GRS_N (1'b1)
	);
wire hs_out;
wire vs_out;
wire de_out;
wire [15:0]yuv_data_out;
wire [7:0]yuv_out;
wire sfp_disable;
wire led;
wire i_p_l1rxn;
wire i_p_l1rxp;
video_sfp_top video_sfp_top
    (
    .rstn(rstn),
    .clk_in1(clk_in1),            // input
    .pix_clk_in(pix_clk_in),      // input
    .hdmi_data_in({yuv_data[15:11],3'b0,yuv_data[10:5],2'b0,yuv_data[4:0],3'b0}),    // input[15:0]
    .hs_in(hs_out_2d),                // input
    .vs_in(vs_out_2d),                // input
    .de_in(de_out_2d),                // input
    .pix_clk_out(pix_clk_out),    // output
    .hdmi_data_out(yuv_data_out),  // output[15:0]
//    .yuv_out(yuv_out),            // output[7:0]
    .hs_out(hs_out),              // output
    .vs_out(vs_out),              // output
    .de_out(de_out),              // output
//    .iic_tx_scl(iic_tx_scl),      // output
//    .iic_tx_sda(iic_tx_sda),      // inout
//    .iic_scl(iic_scl),            // output
//    .iic_sda(iic_sda),            // inout
//    .rstn_out(rstn_out),          // output
    .i_p_refckn_1(i_p_refckn_0),  // input
    .i_p_refckp_1(i_p_refckp_0),  // input
    .i_p_l1rxn(i_p_l1rxn),        // input
    .i_p_l1rxp(i_p_l1rxp),        // input
    .o_p_l1txn(i_p_l1rxn),        // output
    .o_p_l1txp(i_p_l1rxp),        // output
    .sfp_disable(sfp_disable),    // output[1:0]
    .led(led)  ,                   // output
    .o_rxlane_done_1(o_rxlane_done_1)
);


endmodule
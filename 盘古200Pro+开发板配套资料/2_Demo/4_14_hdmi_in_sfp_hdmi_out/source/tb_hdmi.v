module tb_hdmi(

   );

reg clk_in1=0;
reg pix_clk_in=0;
reg rstn=0;
initial begin

#0 ;
pix_clk_in = 0;
rstn = 0;
clk_in1=0;
#200;
rstn = 1;

end
always #(5)  pix_clk_in = ~pix_clk_in;
always #(10)  clk_in1 = ~clk_in1;
wire vs_out_2d;
wire hs_out_2d;
wire de_out_2d;
wire [15:0]yuv_data;


sync_vg_test sync_vg_test
    (
    .clk(pix_clk_in),              // input
    .rstn(rstn),            // input
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
video_sfp_top video_sfp_top
    (
    .clk_in1(clk_in1),            // input
    .pix_clk_in(pix_clk_in),      // input
    .yuv_data_in(yuv_data),    // input[15:0]
    .hs_in(hs_out_2d),                // input
    .vs_in(vs_out_2d),                // input
    .de_in(de_out_2d),                // input
    .pix_clk_out(pix_clk_out),    // output
    .yuv_data_out(yuv_data_out),  // output[15:0]
    .yuv_out(yuv_out),            // output[7:0]
    .hs_out(hs_out),              // output
    .vs_out(vs_out),              // output
    .de_out(de_out),              // output
//    .iic_tx_scl(iic_tx_scl),      // output
//    .iic_tx_sda(iic_tx_sda),      // inout
//    .iic_scl(iic_scl),            // output
//    .iic_sda(iic_sda),            // inout
//    .rstn_out(rstn_out),          // output
//    .i_p_refckn_0(i_p_refckn_0),  // input
//    .i_p_refckp_0(i_p_refckp_0),  // input
//    .i_p_l2rxn(i_p_l2rxn),        // input
//    .i_p_l2rxp(i_p_l2rxp),        // input
//    .o_p_l2txn(o_p_l2txn),        // output
//    .o_p_l2txp(o_p_l2txp),        // output
    .sfp_disable(sfp_disable),    // output[1:0]
    .led(led)                     // output
);


endmodule
// Created by IP Generator (Version 2022.2-SP6.4 build 146967)
// Instantiation Template
//
// Insert the following codes into your Verilog file.
//   * Change the_instance_name to your own instance name.
//   * Change the signal names in the port associations


adc_test the_instance_name (
  .i_rst_n(i_rst_n),                    // input
  .i_apb_pclk(i_apb_pclk),              // input
  .i_apb_paddr(i_apb_paddr),            // input [7:0]
  .i_apb_psel(i_apb_psel),              // input
  .i_apb_enable(i_apb_enable),          // input
  .i_apb_pwrite(i_apb_pwrite),          // input
  .i_apb_pwdata(i_apb_pwdata),          // input [15:0]
  .o_apb_prdata(o_apb_prdata),          // output [15:0]
  .o_apb_pready(o_apb_pready),          // output
  .i_adc_loadsc_n(i_adc_loadsc_n),      // input
  .o_logic_done_a(o_logic_done_a),      // output
  .o_logic_done_b(o_logic_done_b),      // output
  .o_adc_clk_out(o_adc_clk_out),        // output
  .o_adc_dmodified(o_adc_dmodified)     // output
);

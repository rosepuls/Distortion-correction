// Created by IP Generator (Version 2022.1-SP2 build 109751)
// Instantiation Template
//
// Insert the following codes into your Verilog file.
//   * Change the_instance_name to your own instance name.
//   * Change the signal names in the port associations


pll the_instance_name (
  .pll_rst(pll_rst),              // input
  .rstodiv(rstodiv),              // input
  .clkin1(clkin1),                // input
  .clkin2(clkin2),                // input
  .clkin_sel(clkin_sel),          // input
  .clkin_sel_en(clkin_sel_en),    // input
  .dyn_idiv(dyn_idiv),            // input [9:0]
  .dyn_odiv0(dyn_odiv0),          // input [9:0]
  .dyn_fdiv(dyn_fdiv),            // input [9:0]
  .dyn_mdiv(dyn_mdiv),            // input [6:0]
  .pll_lock(pll_lock),            // output
  .clkout0(clkout0)               // output
);

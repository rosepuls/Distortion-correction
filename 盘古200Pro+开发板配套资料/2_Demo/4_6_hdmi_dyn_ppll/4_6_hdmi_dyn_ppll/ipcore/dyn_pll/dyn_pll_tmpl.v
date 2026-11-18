// Created by IP Generator (Version 2022.2-SP6.4 build 146967)
// Instantiation Template
//
// Insert the following codes into your Verilog file.
//   * Change the_instance_name to your own instance name.
//   * Change the signal names in the port associations


dyn_pll the_instance_name (
  .clkout0(clkout0),        // output
  .lock(lock),              // output
  .apb_ready(apb_ready),    // output
  .apb_rdata(apb_rdata),    // output [15:0]
  .clkin1(clkin1),          // input
  .rst(rst),                // input
  .apb_clk(apb_clk),        // input
  .apb_rst_n(apb_rst_n),    // input
  .apb_addr(apb_addr),      // input [4:0]
  .apb_sel(apb_sel),        // input
  .apb_en(apb_en),          // input
  .apb_write(apb_write),    // input
  .apb_wdata(apb_wdata)     // input [15:0]
);

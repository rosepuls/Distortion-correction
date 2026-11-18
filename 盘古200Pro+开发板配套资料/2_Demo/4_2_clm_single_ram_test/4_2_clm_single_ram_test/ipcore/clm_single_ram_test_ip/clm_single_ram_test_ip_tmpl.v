// Created by IP Generator (Version 2022.2-SP6.4 build 146967)
// Instantiation Template
//
// Insert the following codes into your Verilog file.
//   * Change the_instance_name to your own instance name.
//   * Change the signal names in the port associations


clm_single_ram_test_ip the_instance_name (
  .wr_data(wr_data),    // input [1:0]
  .addr(addr),          // input [4:0]
  .clk(clk),            // input
  .wr_en(wr_en),        // input
  .rst(rst),            // input
  .rd_data(rd_data)     // output [1:0]
);

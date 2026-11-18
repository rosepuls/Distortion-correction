// Created by IP Generator (Version 2022.2-SP6.4 build 146967)
// Instantiation Template
//
// Insert the following codes into your Verilog file.
//   * Change the_instance_name to your own instance name.
//   * Change the signal names in the port associations


hsst_test the_instance_name (
  .i_free_clk(i_free_clk),                              // input
  .i_pll_rst_0(i_pll_rst_0),                            // input
  .i_wtchdg_clr_0(i_wtchdg_clr_0),                      // input
  .o_wtchdg_st_0(o_wtchdg_st_0),                        // output [1:0]
  .o_pll_done_0(o_pll_done_0),                          // output
  .o_txlane_done_1(o_txlane_done_1),                    // output
  .o_rxlane_done_1(o_rxlane_done_1),                    // output
  .i_p_refckn_1(i_p_refckn_1),                          // input
  .i_p_refckp_1(i_p_refckp_1),                          // input
  .o_p_clk2core_tx_1(o_p_clk2core_tx_1),                // output
  .i_p_tx1_clk_fr_core(i_p_tx1_clk_fr_core),            // input
  .o_p_clk2core_rx_1(o_p_clk2core_rx_1),                // output
  .i_p_rx1_clk_fr_core(i_p_rx1_clk_fr_core),            // input
  .o_p_pll_lock_0(o_p_pll_lock_0),                      // output
  .o_p_rx_sigdet_sta_1(o_p_rx_sigdet_sta_1),            // output
  .o_p_lx_cdr_align_1(o_p_lx_cdr_align_1),              // output
  .i_p_pcs_word_align_en_1(i_p_pcs_word_align_en_1),    // input
  .i_p_l1rxn(i_p_l1rxn),                                // input
  .i_p_l1rxp(i_p_l1rxp),                                // input
  .o_p_l1txn(o_p_l1txn),                                // output
  .o_p_l1txp(o_p_l1txp),                                // output
  .i_txd_1(i_txd_1),                                    // input [31:0]
  .i_tdispsel_1(i_tdispsel_1),                          // input [3:0]
  .i_tdispctrl_1(i_tdispctrl_1),                        // input [3:0]
  .i_txk_1(i_txk_1),                                    // input [3:0]
  .o_rxstatus_1(o_rxstatus_1),                          // output [2:0]
  .o_rxd_1(o_rxd_1),                                    // output [31:0]
  .o_rdisper_1(o_rdisper_1),                            // output [3:0]
  .o_rdecer_1(o_rdecer_1),                              // output [3:0]
  .o_rxk_1(o_rxk_1)                                     // output [3:0]
);

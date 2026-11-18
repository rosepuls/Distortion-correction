-- Created by IP Generator (Version 2022.2-SP6.4 build 146967)
-- Instantiation Template
--
-- Insert the following codes into your VHDL file.
--   * Change the_instance_name to your own instance name.
--   * Change the net names in the port map.


COMPONENT hsst_test
  PORT (
    i_free_clk : IN STD_LOGIC;
    i_pll_rst_0 : IN STD_LOGIC;
    i_wtchdg_clr_0 : IN STD_LOGIC;
    o_wtchdg_st_0 : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    o_pll_done_0 : OUT STD_LOGIC;
    o_txlane_done_1 : OUT STD_LOGIC;
    o_rxlane_done_1 : OUT STD_LOGIC;
    i_p_refckn_1 : IN STD_LOGIC;
    i_p_refckp_1 : IN STD_LOGIC;
    o_p_clk2core_tx_1 : OUT STD_LOGIC;
    i_p_tx1_clk_fr_core : IN STD_LOGIC;
    o_p_clk2core_rx_1 : OUT STD_LOGIC;
    i_p_rx1_clk_fr_core : IN STD_LOGIC;
    o_p_pll_lock_0 : OUT STD_LOGIC;
    o_p_rx_sigdet_sta_1 : OUT STD_LOGIC;
    o_p_lx_cdr_align_1 : OUT STD_LOGIC;
    i_p_pcs_word_align_en_1 : IN STD_LOGIC;
    i_p_l1rxn : IN STD_LOGIC;
    i_p_l1rxp : IN STD_LOGIC;
    o_p_l1txn : OUT STD_LOGIC;
    o_p_l1txp : OUT STD_LOGIC;
    i_txd_1 : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    i_tdispsel_1 : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    i_tdispctrl_1 : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    i_txk_1 : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    o_rxstatus_1 : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    o_rxd_1 : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    o_rdisper_1 : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    o_rdecer_1 : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    o_rxk_1 : OUT STD_LOGIC_VECTOR(3 DOWNTO 0)
  );
END COMPONENT;


the_instance_name : hsst_test
  PORT MAP (
    i_free_clk => i_free_clk,
    i_pll_rst_0 => i_pll_rst_0,
    i_wtchdg_clr_0 => i_wtchdg_clr_0,
    o_wtchdg_st_0 => o_wtchdg_st_0,
    o_pll_done_0 => o_pll_done_0,
    o_txlane_done_1 => o_txlane_done_1,
    o_rxlane_done_1 => o_rxlane_done_1,
    i_p_refckn_1 => i_p_refckn_1,
    i_p_refckp_1 => i_p_refckp_1,
    o_p_clk2core_tx_1 => o_p_clk2core_tx_1,
    i_p_tx1_clk_fr_core => i_p_tx1_clk_fr_core,
    o_p_clk2core_rx_1 => o_p_clk2core_rx_1,
    i_p_rx1_clk_fr_core => i_p_rx1_clk_fr_core,
    o_p_pll_lock_0 => o_p_pll_lock_0,
    o_p_rx_sigdet_sta_1 => o_p_rx_sigdet_sta_1,
    o_p_lx_cdr_align_1 => o_p_lx_cdr_align_1,
    i_p_pcs_word_align_en_1 => i_p_pcs_word_align_en_1,
    i_p_l1rxn => i_p_l1rxn,
    i_p_l1rxp => i_p_l1rxp,
    o_p_l1txn => o_p_l1txn,
    o_p_l1txp => o_p_l1txp,
    i_txd_1 => i_txd_1,
    i_tdispsel_1 => i_tdispsel_1,
    i_tdispctrl_1 => i_tdispctrl_1,
    i_txk_1 => i_txk_1,
    o_rxstatus_1 => o_rxstatus_1,
    o_rxd_1 => o_rxd_1,
    o_rdisper_1 => o_rdisper_1,
    o_rdecer_1 => o_rdecer_1,
    o_rxk_1 => o_rxk_1
  );

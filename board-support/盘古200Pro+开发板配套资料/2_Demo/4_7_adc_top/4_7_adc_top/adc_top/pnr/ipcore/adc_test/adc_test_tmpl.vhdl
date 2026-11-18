-- Created by IP Generator (Version 2022.2-SP6.4 build 146967)
-- Instantiation Template
--
-- Insert the following codes into your VHDL file.
--   * Change the_instance_name to your own instance name.
--   * Change the net names in the port map.


COMPONENT adc_test
  PORT (
    i_rst_n : IN STD_LOGIC;
    i_apb_pclk : IN STD_LOGIC;
    i_apb_paddr : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    i_apb_psel : IN STD_LOGIC;
    i_apb_enable : IN STD_LOGIC;
    i_apb_pwrite : IN STD_LOGIC;
    i_apb_pwdata : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    o_apb_prdata : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    o_apb_pready : OUT STD_LOGIC;
    i_adc_loadsc_n : IN STD_LOGIC;
    o_logic_done_a : OUT STD_LOGIC;
    o_logic_done_b : OUT STD_LOGIC;
    o_adc_clk_out : OUT STD_LOGIC;
    o_adc_dmodified : OUT STD_LOGIC
  );
END COMPONENT;


the_instance_name : adc_test
  PORT MAP (
    i_rst_n => i_rst_n,
    i_apb_pclk => i_apb_pclk,
    i_apb_paddr => i_apb_paddr,
    i_apb_psel => i_apb_psel,
    i_apb_enable => i_apb_enable,
    i_apb_pwrite => i_apb_pwrite,
    i_apb_pwdata => i_apb_pwdata,
    o_apb_prdata => o_apb_prdata,
    o_apb_pready => o_apb_pready,
    i_adc_loadsc_n => i_adc_loadsc_n,
    o_logic_done_a => o_logic_done_a,
    o_logic_done_b => o_logic_done_b,
    o_adc_clk_out => o_adc_clk_out,
    o_adc_dmodified => o_adc_dmodified
  );

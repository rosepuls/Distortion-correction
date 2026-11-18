-- Created by IP Generator (Version 2022.2-SP6.4 build 146967)
-- Instantiation Template
--
-- Insert the following codes into your VHDL file.
--   * Change the_instance_name to your own instance name.
--   * Change the net names in the port map.


COMPONENT dyn_pll
  PORT (
    clkout0 : OUT STD_LOGIC;
    lock : OUT STD_LOGIC;
    apb_ready : OUT STD_LOGIC;
    apb_rdata : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    clkin1 : IN STD_LOGIC;
    rst : IN STD_LOGIC;
    apb_clk : IN STD_LOGIC;
    apb_rst_n : IN STD_LOGIC;
    apb_addr : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
    apb_sel : IN STD_LOGIC;
    apb_en : IN STD_LOGIC;
    apb_write : IN STD_LOGIC;
    apb_wdata : IN STD_LOGIC_VECTOR(15 DOWNTO 0)
  );
END COMPONENT;


the_instance_name : dyn_pll
  PORT MAP (
    clkout0 => clkout0,
    lock => lock,
    apb_ready => apb_ready,
    apb_rdata => apb_rdata,
    clkin1 => clkin1,
    rst => rst,
    apb_clk => apb_clk,
    apb_rst_n => apb_rst_n,
    apb_addr => apb_addr,
    apb_sel => apb_sel,
    apb_en => apb_en,
    apb_write => apb_write,
    apb_wdata => apb_wdata
  );

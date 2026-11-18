-- Created by IP Generator (Version 2022.1-SP2 build 109751)
-- Instantiation Template
--
-- Insert the following codes into your VHDL file.
--   * Change the_instance_name to your own instance name.
--   * Change the net names in the port map.


COMPONENT pll
  PORT (
    pll_rst : IN STD_LOGIC;
    rstodiv : IN STD_LOGIC;
    clkin1 : IN STD_LOGIC;
    clkin2 : IN STD_LOGIC;
    clkin_sel : IN STD_LOGIC;
    clkin_sel_en : IN STD_LOGIC;
    dyn_idiv : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    dyn_odiv0 : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    dyn_fdiv : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
    dyn_mdiv : IN STD_LOGIC_VECTOR(6 DOWNTO 0);
    pll_lock : OUT STD_LOGIC;
    clkout0 : OUT STD_LOGIC
  );
END COMPONENT;


the_instance_name : pll
  PORT MAP (
    pll_rst => pll_rst,
    rstodiv => rstodiv,
    clkin1 => clkin1,
    clkin2 => clkin2,
    clkin_sel => clkin_sel,
    clkin_sel_en => clkin_sel_en,
    dyn_idiv => dyn_idiv,
    dyn_odiv0 => dyn_odiv0,
    dyn_fdiv => dyn_fdiv,
    dyn_mdiv => dyn_mdiv,
    pll_lock => pll_lock,
    clkout0 => clkout0
  );

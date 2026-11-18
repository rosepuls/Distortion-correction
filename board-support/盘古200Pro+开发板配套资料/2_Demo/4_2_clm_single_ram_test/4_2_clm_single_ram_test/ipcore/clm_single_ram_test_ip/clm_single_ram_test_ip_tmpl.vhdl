-- Created by IP Generator (Version 2022.2-SP6.4 build 146967)
-- Instantiation Template
--
-- Insert the following codes into your VHDL file.
--   * Change the_instance_name to your own instance name.
--   * Change the net names in the port map.


COMPONENT clm_single_ram_test_ip
  PORT (
    wr_data : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    addr : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
    clk : IN STD_LOGIC;
    wr_en : IN STD_LOGIC;
    rst : IN STD_LOGIC;
    rd_data : OUT STD_LOGIC_VECTOR(1 DOWNTO 0)
  );
END COMPONENT;


the_instance_name : clm_single_ram_test_ip
  PORT MAP (
    wr_data => wr_data,
    addr => addr,
    clk => clk,
    wr_en => wr_en,
    rst => rst,
    rd_data => rd_data
  );

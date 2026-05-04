-- Handwritten project-level clock wizard wrapper for the final project.
-- Input clock: 37.5 MHz from the DDR2 RAM interface clkout
-- Outputs: two 100 MHz clocks for project-level logic domains

library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity project_clk_wiz_37p5_to_100 is
port
 (
  CLK_IN1  : in  std_logic;
  CLK_OUT1 : out std_logic;
  CLK_OUT2 : out std_logic;
  RESET    : in  std_logic;
  LOCKED   : out std_logic
 );
end project_clk_wiz_37p5_to_100;

architecture xilinx of project_clk_wiz_37p5_to_100 is
  signal clkin1         : std_logic;
  signal clkfbout       : std_logic;
  signal clkfbout_buf   : std_logic;
  signal clkout0        : std_logic;
  signal clkout1        : std_logic;
  signal clkout2_unused : std_logic;
  signal clkout3_unused : std_logic;
  signal clkout4_unused : std_logic;
  signal clkout5_unused : std_logic;
begin

  -- The DDR2 wrapper already provides `CLK_IN1` on a global clock network.
  -- Do not re-buffer it here, or Spartan-6 implementation will see a BUFG
  -- driving the input buffer of another clocking block.
  clkin1 <= CLK_IN1;

  -- 37.5 MHz * 16 / 6 = 100 MHz
  pll_base_inst : PLL_BASE
  generic map
   (BANDWIDTH          => "OPTIMIZED",
    CLK_FEEDBACK       => "CLKFBOUT",
    COMPENSATION       => "SYSTEM_SYNCHRONOUS",
    DIVCLK_DIVIDE      => 1,
    CLKFBOUT_MULT      => 16,
    CLKFBOUT_PHASE     => 0.000,
    CLKOUT0_DIVIDE     => 6,
    CLKOUT0_PHASE      => 0.000,
    CLKOUT0_DUTY_CYCLE => 0.500,
    CLKOUT1_DIVIDE     => 6,
    CLKOUT1_PHASE      => 0.000,
    CLKOUT1_DUTY_CYCLE => 0.500,
    CLKIN_PERIOD       => 26.667,
    REF_JITTER         => 0.010)
  port map
   (CLKFBOUT => clkfbout,
    CLKOUT0  => clkout0,
    CLKOUT1  => clkout1,
    CLKOUT2  => clkout2_unused,
    CLKOUT3  => clkout3_unused,
    CLKOUT4  => clkout4_unused,
    CLKOUT5  => clkout5_unused,
    LOCKED   => LOCKED,
    RST      => RESET,
    CLKFBIN  => clkfbout_buf,
    CLKIN    => clkin1);

  clkf_buf : BUFG
  port map
   (O => clkfbout_buf,
    I => clkfbout);

  clkout1_buf : BUFG
  port map
   (O => CLK_OUT1,
    I => clkout0);

  -- Feed the codec-local clock wizard from the raw PLL output. The downstream
  -- clock wizard performs its own input buffering, so adding a BUFG here
  -- creates a forbidden BUFG-to-BUFG style route in Spartan-6.
  CLK_OUT2 <= clkout1;

end xilinx;

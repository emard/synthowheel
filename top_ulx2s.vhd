-- Author: Emard
-- License: BSD

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use ieee.numeric_std.all; -- we need signed type
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.MATH_REAL.ALL;

-- vendor specific libs (lattice)
library xp2;
use xp2.components.all;

entity top_synth is
  generic (
    C_clk_freq: integer := 25;
    C_pcm: boolean := true
  );
  port (
    clk_25m: in std_logic;
    rs232_tx: out std_logic;
    rs232_rx: in std_logic;
    p_ring: out std_logic;
    p_tip: out std_logic_vector(3 downto 0);
    led: out std_logic_vector(7 downto 0);
    btn_left, btn_right, btn_up, btn_down, btn_center: in std_logic;
    sw: in std_logic_vector(3 downto 0);
    j1_2, j1_3, j1_4, j1_8, j1_9, j1_13, j1_14, j1_15: inout std_logic;
    j1_16, j1_17, j1_18, j1_19, j1_20, j1_21, j1_22, j1_23: inout std_logic;
    j2_2, j2_3, j2_4, j2_5, j2_6, j2_7, j2_8, j2_9: inout std_logic;
    j2_10, j2_11, j2_12, j2_13, j2_16: inout std_logic
  );
end;

architecture Behavioral of top_synth is
  signal clk: std_logic;
  signal btn: std_logic_vector(4 downto 0);
  signal S_pcm: signed(16 downto 0);
  signal S_out_l, S_out_r: std_logic;
begin
  clk <= clk_25m;
  btn <= btn_left & btn_right & btn_up & btn_down & btn_center;
  
  led(4 downto 0) <= btn;

--  inst_synth: entity work.synth
--    generic map (
--      C_voice_addr_bits => 2,
--      C_out_data => 16
--    )
--    port map (
--      clk => clk,
--      pcm_out => S_pcm
--    );

    inst_pcm: entity work.pcm
    port map
    (
        clk => clk,
        in_pcm_l => S_pcm,
        in_pcm_r => S_pcm,
        out_l => S_out_l,
        out_r => S_out_r
    );

    p_tip <= S_out_l;
    p_ring <= (others => S_out_r);
end Behavioral;
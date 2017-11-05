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
    C_clk_freq: integer := 25000000; -- Hz clock
    C_ref_freq: real := 440.0; -- Hz reference tone A4 (normally 440 Hz)
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
  constant C_pcm_bits: integer := 24; -- 24 bits to match SPDIF output
  constant C_pwm_bits: integer := 12; -- less or equal C_pcm bits, 12 works well
  signal clk: std_logic;
  signal btn: std_logic_vector(6 downto 0);
  signal S_pcm: signed(C_pcm_bits-1 downto 0);
  signal S_pwm: std_logic;
  signal S_spdif_out: std_logic;
begin
  clk <= clk_25m;
  btn <= "00" & btn_left & btn_right & btn_up & btn_down & btn_center; -- center button is tone A4

  inst_synth: entity work.synth
    generic map
    (
      C_clk_freq => C_clk_freq,
      C_ref_freq => C_ref_freq,
      --C_ref_octave => 5, -- 5 means octave 4
      --C_ref_tone => 9, -- 9 means note A
      --C_voice_addr_bits => 7, -- 7:128 tones, MIDI keys
      -- setting both voice_vol_bits and wav_data_bits to 9 to use small 9x9 multiplier
      --C_voice_vol_bits => 10, -- 9: bits signed data for volume of each voice
      --C_wav_data_bits => 12, -- 9: bits signed wave amplitude resolution
      --C_wav_addr_bits => 10, -- 10: bits wave function table
      --C_pa_bits => 32, -- 32: 2-BRAM precise tuning, 19: 1-BRAM coarse tuning
      C_keyboard => true,
      C_zero_cross => true,
      C_out_bits => C_pcm_bits,
      C_amplify => 0
    )
    port map
    (
      clk => clk,
      io_ce => '0',
      io_bus_write => '0',
      io_byte_sel => (others => '0'),
      io_addr => (others => '0'),
      io_bus_in => (others => '0'),
      keyboard => btn,
      pcm_out => S_pcm
    );

  led <= std_logic_vector(S_pcm(S_pcm'length-1 downto S_pcm'length-led'length));

  inst_sigmadelta: entity work.sigmadelta
    generic map
    (
      C_bits => C_pwm_bits
    )
    port map
    (
      clk => clk,
      in_pcm => S_pcm(S_pcm'length-1 downto S_pcm'length-C_pwm_bits),
      out_pwm => S_pwm
    );

  -- spdif_tx needs 24-bit signed input
  inst_spdif_tx: entity work.spdif_tx
  generic map
  (
    C_clk_freq => C_clk_freq
  )
  port map
  (
    clk => clk,
    data_in => std_logic_vector(S_pcm),
    spdif_out => S_spdif_out
  );

  p_ring <= S_pwm;
  p_tip <= "00" & S_spdif_out & S_spdif_out;
  j1_19 <= S_pwm; -- to monitor with oscilloscope

end Behavioral;

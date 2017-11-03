-- Author: Emard
-- License: BSD

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
-- use IEEE.STD_LOGIC_ARITH.ALL;
use ieee.numeric_std.all; -- we need signed type
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.MATH_REAL.ALL;

entity top_synth is
  generic (
    C_clk_freq: integer := 50000000; -- Hz
    C_ref_freq: real := 440.0; -- Hz tone A4 (normally 440 Hz)
    C_pcm: boolean := true
  );
  port (
    clk_50MHz: in std_logic;
    rs232_tx: out std_logic;
    rs232_rx: in std_logic;
    audio1, audio2: out std_logic; -- 3.5mm audio jack
    leds: out std_logic_vector(7 downto 0);
    sw: in std_logic_vector(4 downto 1);
    porta, portb, portc: inout std_logic_vector(11 downto 0);
    portd: inout std_logic_vector(3 downto 0); -- fm and cw antennas are here
    porte, portf: inout std_logic_vector(11 downto 0)
  );
end;

architecture Behavioral of top_synth is
  signal clk: std_logic;
  signal btn: std_logic_vector(6 downto 0);
  signal S_pcm: signed(15 downto 0);
  signal S_pwm: std_logic;
  signal S_spdif_sample: std_logic_vector(23 downto 0);
  signal S_spdif_sample_pad: signed(7 downto 0);
  signal S_spdif_out: std_logic;
begin
  clk <= clk_50MHz;
  
  rs232_tx <= '1';

  btn <= "000" & sw;

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
      C_amplify => 4
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

  leds <= std_logic_vector(S_pcm(S_pcm'length-1 downto S_pcm'length-leds'length));

  inst_sigmadelta: entity work.sigmadelta
    port map
    (
        clk => clk,
        in_pcm => S_pcm,
        out_pwm => S_pwm
    );

  -- LSB padding
  S_spdif_sample_pad <= (others => S_pcm(0));
  -- sending signed 24-bit PCM data (padded)
  S_spdif_sample <= std_logic_vector( S_pcm & S_spdif_sample_pad );
  -- conversion to unsigned PCM
  -- by inverting MSB bit (effectively adding 0x8000)
  -- and downshfting by 1 bit (sending effectively 23-bit data)
  -- S_spdif_sample <= std_logic_vector( '0' & (not S_pcm(15)) & S_pcm(14 downto 0) & S_spdif_sample_pad );
  inst_spdif_tx: entity work.spdif_tx
  generic map
  (
    C_clk_freq => C_clk_freq
  )
  port map
  (
    clk => clk,
    data_in => S_spdif_sample,
    spdif_out => S_spdif_out
  );

  audio1 <= S_pwm;
  audio2 <= S_spdif_out;

end Behavioral;

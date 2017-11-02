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
  signal btn: std_logic_vector(4 downto 0);
  signal S_pcm: signed(15 downto 0);
  signal S_out_l, S_out_r: std_logic;
  signal R_buzzer: signed(16 downto 0); -- tone generator for testing
begin
  clk <= clk_50MHz;
  
  rs232_tx <= '1';
  
  inst_synth: entity work.synth
    generic map
    (
      C_clk_freq => C_clk_freq,
      C_ref_freq => C_ref_freq,
      C_amplify => 6
    )
    port map 
    (
      clk => clk,
      bus_ce => '0',
      bus_write => '0',
      bus_byte_sel => (others => '0'),
      bus_addr => (others => '0'),
      bus_in => (others => '0'),
      pcm_out => S_pcm
    );

  leds <= std_logic_vector(S_pcm(S_pcm'length-1 downto S_pcm'length-leds'length));
  
  process(clk)
  begin
    if rising_edge(clk)
    then
      R_buzzer <= R_buzzer + 1;
    end if;
  end process;
  
  inst_pcm: entity work.pcm
    port map
    (
        clk => clk,
        in_pcm_l => S_pcm,
        in_pcm_r => S_pcm, -- debug: R_buzzer(R_buzzer'length-1 downto R_buzzer'length-16),
        out_l => S_out_l,
        out_r => S_out_r
    );

  audio1 <= S_out_r;
  audio2 <= S_out_l;
end Behavioral;

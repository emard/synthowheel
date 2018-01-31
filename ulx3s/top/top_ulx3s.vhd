----------------------------
-- ULX3S Top level for ORAO
-- http://github.com/emard
----------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

library ecp5u;
use ecp5u.components.all;

entity top_synth is
generic
(
    C_clk_freq: integer := 25000000; -- Hz clock
    C_ref_freq: real := 440.0; -- Hz reference tone A4 (normally 440 Hz)
    C_pcm: boolean := true
);
port
(
  clk_25MHz: in std_logic;  -- main clock input from 25MHz clock source

  -- UART0 (FTDI USB slave serial)
  ftdi_rxd: out   std_logic;
  ftdi_txd: in    std_logic;
  -- FTDI additional signaling
  ftdi_ndsr: inout  std_logic;
  ftdi_nrts: inout  std_logic;
  ftdi_txden: inout std_logic;

  -- UART1 (WiFi serial)
  wifi_rxd: out   std_logic;
  wifi_txd: in    std_logic;
  -- WiFi additional signaling
  wifi_en: inout  std_logic := 'Z'; -- '0' will disable wifi by default
  wifi_gpio0, wifi_gpio2, wifi_gpio16, wifi_gpio17: inout std_logic := 'Z';

  -- ADC MAX11123
  adc_csn, adc_sclk, adc_mosi: out std_logic;
  adc_miso: in std_logic;

  -- SDRAM
  sdram_clk: out std_logic;
  sdram_cke: out std_logic;
  sdram_csn: out std_logic;
  sdram_rasn: out std_logic;
  sdram_casn: out std_logic;
  sdram_wen: out std_logic;
  sdram_a: out std_logic_vector (12 downto 0);
  sdram_ba: out std_logic_vector(1 downto 0);
  sdram_dqm: out std_logic_vector(1 downto 0);
  sdram_d: inout std_logic_vector (15 downto 0);

  -- Onboard blinky
  led: out std_logic_vector(7 downto 0);
  btn: in std_logic_vector(6 downto 0);
  sw: in std_logic_vector(3 downto 0);
  oled_csn, oled_clk, oled_mosi, oled_dc, oled_resn: out std_logic;

  -- GPIO
  gp, gn: inout std_logic_vector(27 downto 0);

  -- SHUTDOWN: logic '1' here will shutdown power on PCB >= v1.7.5
  shutdown: out std_logic := '0';

  -- Audio jack 3.5mm
  audio_l, audio_r, audio_v: inout std_logic_vector(3 downto 0) := (others => 'Z');

  -- Onboard antenna 433 MHz
  ant_433mhz: out std_logic;

  -- Digital Video (differential outputs needs differential buffers)
  --gpdi_dp, gpdi_dn: out std_logic_vector(2 downto 0);
  --gpdi_clkp, gpdi_clkn: out std_logic;

  -- i2c shared for digital video and RTC
  gpdi_scl, gpdi_sda: inout std_logic;

  -- US2 port
  usb_fpga_dp, usb_fpga_dn: inout std_logic;

  -- Flash ROM (SPI0)
  -- commented out because it can't be used as GPIO
  -- when bitstream is loaded from config flash
  --flash_miso   : in      std_logic;
  --flash_mosi   : out     std_logic;
  --flash_clk    : out     std_logic;
  --flash_csn    : out     std_logic;

  -- SD card (SPI1)
  sd_dat3_csn, sd_cmd_di, sd_dat0_do, sd_dat1_irq, sd_dat2: inout std_logic;
  sd_clk: out std_logic;
  sd_cdn, sd_wp: in std_logic
);
end;

architecture struct of top_synth is
  constant C_pcm_bits: integer := 24; -- 24 bits to match SPDIF output
  constant C_pwm_bits: integer := 12; -- less or equal C_pcm bits, 12 works well
  signal clk: std_logic;
  signal S_pcm: signed(C_pcm_bits-1 downto 0);
  signal S_pwm: std_logic;
  signal S_spdif_out: std_logic;
begin
  wifi_gpio0 <= btn(0); -- holding reset for 2 sec will activate ESP32 loader
  clk <= clk_25MHz;

  inst_synth: entity work.synth
    generic map
    (
      C_clk_freq => C_clk_freq,
      C_ref_freq => C_ref_freq,
      C_ref_octave => 5, -- 5 means octave 4
      C_ref_tone => 9, -- 9 means note A
      --C_voice_addr_bits => 7, -- 7:128 tones, MIDI keys
      -- setting both voice_vol_bits and wav_data_bits to 9 to use small 9x9 multiplier
      --C_voice_vol_bits => 9, -- 9: bits signed data for volume of each voice
      --C_wav_data_bits => 9, -- 9: bits signed wave amplitude resolution
      --C_wav_addr_bits => 10, -- 10: bits wave function table
      --C_pa_data_bits => 32, -- 32: 2-BRAM precise tuning, 19: 1-BRAM coarse tuning
      C_keyboard => true,
      C_zero_cross => true,
      C_out_bits => C_pcm_bits,
      C_multiplier => false, -- signed multiplier disabled, doesn't infer properly on ECP5?
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
      keyboard => btn(6 downto 1) & not btn(0),
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

  audio_l(1 downto 0) <= (others => S_pwm);
  audio_r(1 downto 0) <= (others => S_pwm);
  audio_v(1 downto 0) <= (others => S_spdif_out);

end struct;

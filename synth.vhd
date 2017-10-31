-- RDS modulator with DBPSK
-- (c) Davor Jadrijevic
-- LICENSE=BSD

-- this module generates multiple-voice polyphonic sound

library ieee;
use ieee.std_logic_1164.all;
-- use ieee.std_logic_arith.all; -- replaced by ieee.numeric_std.all
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;
use ieee.math_real.all;

entity synth is
generic
(
  C_voice_addr_bits: integer := 7; -- 7: 128 voices (counters, volume multipliers)
  C_voice_vol_bits: integer := 16; -- 16: 16-bit signed data for volume
  C_wav_addr_bits: integer := 10;  -- 10: 10-bit unsigned data for time base
  C_wav_data_bits: integer := 16;
  C_timebase_var_bits: integer := 20; -- 20 bits for array data of timebase BRAM memory for addition
  C_tones_per_octave: integer := 12;
  C_out_data: integer := 16 -- 16-bit of signed accumulator data (PCM)
);
port
(
  clk: in std_logic;
  led: out std_logic_vector(7 downto 0);
  pcm_out: out signed(15 downto 0) -- to audio output
);
end;

architecture RTL of synth is
    -- TODO:
    -- meantone temperament:
    -- see https://en.wikipedia.org/wiki/Semitone
    -- and https://en.wikipedia.org/wiki/Chromatic_scale
    -- tone cents table, 0-1200 full octave of 12 tones
    -- no pitch cents
    --  0 C       0.0
    --  1 C#     76.0
    --  2 D     193.2
    --  3 Eb    310.3
    --  4 E     386.3
    --  5 F     503.4
    --  6 F#    579.5
    --  7 G     696.6
    --  8 G#    772.6
    --  9 A     889.7
    -- 10 Bb   1006.8
    -- 11 B    1082.9
    -- 12 C    1200.0

    -- just intonaton
    -- C	C♯	D♭	D	D♯	E♭	E	E♯/F♭	F	F♯	G♭	G	G♯	A♭	A	A♯	B♭	B	B♯/C♭	C
    -- 1 	25/24 	16/15 	9/8 	75/64 	6/5 	5/4 	32/25 	4/3 	25/18 	36/25 	3/2 	25/16 	8/5 	5/3 	125/72 	9/5 	15/8 	48/25 	2

    -- pythagorean tuning
    -- C	D♭	C♯		D 	E♭ 	D♯ 		E 	F 	F♯ 		G♭ 	G 	A♭ 	G♯		A 	B♭ 	A♯ 		B 	C
    -- 1 	256/243 2187/2048 	9/8 	32/27 	8192/6561 	81/64 	4/3 	1024/729 	729/512 3/2 	128/81 	6561/4096 	27/16 	16/9 	4096/2187 	243/128 2

    constant C_timebase_const_bits: integer := C_timebase_var_bits-C_wav_addr_bits; -- bits for timebase addition constants
    constant C_accu_data: integer := C_timebase_var_bits+C_voice_addr_bits+C_wav_addr_bits; -- hopfully good enough accumulator register width

    constant C_wav_table_len: integer := 2**C_wav_addr_bits;
    type T_wav_table is array (0 to C_wav_table_len-1) of signed(C_wav_data_bits-1 downto 0);
    function F_wav_table(len: integer; bits: integer)
      return T_wav_table is
        variable i: integer;
        variable y: T_wav_table;
    begin
      for i in 0 to len - 1 loop
        y(i) := to_signed(integer(sin(real(i)*2.0*3.141592653589793/real(len)) * (2.0**real(bits-1)-1.0)), C_wav_data_bits); -- converts sinewave floats to signed number
      end loop;
      return y;
    end F_wav_table;
    constant C_wav_table: T_wav_table := F_wav_table(C_wav_table_len, C_wav_data_bits); -- wave table initializer len, amplitude
    
    -- the data type and initializer for the frequencies table
    constant C_voice_table_len: integer := 2**C_voice_addr_bits;
    type T_freq_table is array (0 to C_voice_table_len-1) of unsigned(C_timebase_const_bits-1 downto 0);
    function F_freq_table(len: integer; tones_per_octave: integer; bits: integer)
      return T_freq_table is
        variable i: integer;
        variable y: T_freq_table;
    begin
      for i in 0 to len - 1 loop
        y(i) := to_unsigned(integer(2.0**(real(i)/real(tones_per_octave)) * 2.0**(real(bits)-real(len)/real(tones_per_octave))), C_timebase_const_bits);
      end loop;
      return y;
    end F_freq_table;
    constant C_freq_table_len: integer := 2**C_timebase_const_bits;
    constant C_freq_table: T_freq_table := F_freq_table(C_voice_table_len, C_tones_per_octave, C_timebase_const_bits); -- wave table initializer len, freq

    -- the voice volume constant array for testing
    -- replace this ith dual port BRAM where CPU writes and synth reads values
    type T_voice_vol_table is array (0 to C_voice_table_len-1) of signed(C_voice_vol_bits-1 downto 0);
    function F_voice_vol_table(len: integer; bits: integer)
      return T_voice_vol_table is
        variable i: integer;
        variable y: T_voice_vol_table;
    begin
      for i in 0 to len - 1 loop
        if i = 1 or i = 24 or i = 60 or i = 120 then -- which voices to enable
          y(i) := to_signed(2**(C_voice_vol_bits-1)-1, C_voice_vol_bits); -- one voice max positive volume
        else
          y(i) := to_signed(0, C_voice_vol_bits); -- others muted
        end if;
      end loop;
      return y;
    end F_voice_vol_table;
    constant C_voice_vol_table: T_voice_vol_table := F_voice_vol_table(C_voice_table_len, C_voice_vol_bits); -- vol table for testing
    signal R_voice, S_tb_write_addr: std_logic_vector(C_voice_addr_bits-1 downto 0); -- currently processed voice, destination of increment
    signal S_tb_read_data, S_tb_write_data: std_logic_vector(C_timebase_var_bits-1 downto 0); -- current and next timebase
    signal S_voice_vol: signed(C_voice_vol_bits-1 downto 0);
    signal S_wav_data: signed(C_wav_data_bits-1 downto 0);
    signal R_multiplied: signed(C_voice_vol_bits+C_wav_data_bits-1 downto 0);
    signal R_accu: signed(C_accu_data-1 downto 0);
    signal R_output: signed(C_out_data-1 downto 0); 
    signal R_led: std_logic_vector(7 downto 0); -- will appear to board LEDs
begin
    -- increment voice number that is currently processed
    process(clk)
    begin
      if rising_edge(clk) then
        R_voice <= R_voice + 1;
        if conv_integer(R_voice) = 121 then
          -- R_led <= S_tb_read_data(S_tb_read_data'length-1 downto S_tb_read_data'length-R_led'length);
          -- R_led <= std_logic_vector(S_wav_data(S_wav_data'length-1 downto S_wav_data'length-R_led'length));
          R_led <= std_logic_vector(R_multiplied(R_multiplied'length-1 downto R_multiplied'length-R_led'length));
        end if; 
      end if;
    end process;
    -- R_voice contains current address of the voice amplitude and frequency table

    -- increment the time base array in the BRAM
    S_tb_write_data <= S_tb_read_data + to_integer(C_freq_table(conv_integer(R_voice))); -- next time base incremented with frequency
    -- S_tb_write_data <= S_tb_read_data + 1; -- debug: next time base incremented with frequency
    -- next value is written on previous address to match register pipeline latency
    S_tb_write_addr <= R_voice - 1;
    timebase_bram: entity work.bram_true2p_1clk
    generic map
    (
        dual_port => true,
        addr_width => C_voice_addr_bits,
        data_width => C_timebase_var_bits
    )
    port map
    (
        clk => clk,
        we_a => '1', -- always write increments
        addr_a => S_tb_write_addr,
        data_in_a => S_tb_write_data,
        we_b => '0', -- always read 
        addr_b => R_voice,
        data_out_b => S_tb_read_data
    );

    -- voice volume reading
    -- get from addressed BRAM the volume of current voice
    S_voice_vol <= C_voice_vol_table(conv_integer(R_voice)); -- connect to bram read output, address R_Voice
    -- waveform data reading
    S_wav_data <= C_wav_table(conv_integer(S_tb_read_data(C_timebase_var_bits-1 downto C_timebase_var_bits-C_wav_addr_bits)));

    -- multiply, store result to register and add register to accumulator
    process(clk)
    begin
      if rising_edge(clk) then
        -- S_voice_vol must be signed, then max amplitude is 2x smaller
        R_multiplied <= S_voice_vol * S_wav_data;
        if R_voice = 0 then
          R_output <= R_accu(C_accu_data-1 downto C_accu_data-C_out_data);
          R_accu <= (others => '0'); -- reset accumulator
        else
          R_accu <= R_accu + R_multiplied;
        end if;
      end if;
    end process;
    
    led <= R_led;
    pcm_out <= R_accu(R_accu'length-1 downto R_accu'length-pcm_out'length);
end;

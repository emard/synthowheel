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
  C_clk_freq: integer := 25000000; -- Hz input clock
  C_a4_freq: real := 440.0; -- Hz tone A4 tuning
  C_voice_addr_bits: integer := 7; -- bits voices (2^n voices, timebase counters, volume multipliers)
  C_voice_vol_bits: integer := 10; -- bits signed data for volume of each voice
  C_wav_addr_bits: integer := 10;  -- bits unsigned address for wave time base (time resolution)
  C_wav_data_bits: integer := 12; -- bits signed wave amplitude resolution
  C_shift_octave: integer := 6; -- tuning by full n octaves. larger value have highier tuning resolution while highest n octaves will get coarser timestep
  C_tuning: real range 0.0 to 1200.0 := 0.0; -- cents (1/1200 octave) fine tuning
  C_timebase_var_bits: integer := 32; -- bits for array data of timebase BRAM (phase accumulator)
  C_amplify: integer := 0; -- bits louder output but reduces max number of voices by 2^n (clipping)
  C_tones_per_octave: integer := 12; -- tones per octave (don't touch)
  C_out_bits: integer := 16 -- bits of signed accumulator data (PCM)
);
port
(
  clk: in std_logic;
  -- led: out std_logic_vector(7 downto 0);
  pcm_out: out signed(15 downto 0) -- to audio output
);
end;

architecture RTL of synth is

    constant C_accu_bits: integer := C_voice_vol_bits+C_wav_data_bits+C_voice_addr_bits-C_amplify-1; -- accumulator register width

    -- meantone temperament:
    -- see https://en.wikipedia.org/wiki/Semitone
    -- and https://en.wikipedia.org/wiki/Chromatic_scale
    -- tone cents table f=2^(x/1200), 0-1200 scale for full octave of 12 tones
    type T_halftone_temperament is array (0 to C_tones_per_octave-1) of real;
    constant C_halftone_temperament: T_halftone_temperament :=
    (
         0.0, --  0 C
        76.0, --  1 C#
       193.2, --  2 D
       310.3, --  3 Eb
       386.3, --  4 E
       503.4, --  5 F
       579.5, --  6 F#
       696.6, --  7 G
       772.6, --  8 G#
       889.7, --  9 A
      1006.8, -- 10 Bb
      1082.9  -- 11 B
    );
    
    -- other temperaments (freq scale)
    -- just intonaton
    -- C	C♯	D♭	D	D♯	E♭	E	E♯/F♭	F	F♯	G♭	G	G♯	A♭	A	A♯	B♭	B	B♯/C♭	C
    -- 1 	25/24 	16/15 	9/8 	75/64 	6/5 	5/4 	32/25 	4/3 	25/18 	36/25 	3/2 	25/16 	8/5 	5/3 	125/72 	9/5 	15/8 	48/25 	2

    -- pythagorean tuning
    -- C	D♭	C♯		D 	E♭ 	D♯ 		E 	F 	F♯ 		G♭ 	G 	A♭ 	G♯		A 	B♭ 	A♯ 		B 	C
    -- 1 	256/243 2187/2048 	9/8 	32/27 	8192/6561 	81/64 	4/3 	1024/729 	729/512 3/2 	128/81 	6561/4096 	27/16 	16/9 	4096/2187 	243/128 2
    
    -- tuning math:
    -- input: C_clk_freq, C_A4_freq, C_wav_addr_bits, C_voice_addr_bits
    -- output: C_shift_octave, C_tuning

    constant C_wav_table_len: integer := 2**C_wav_addr_bits;
    type T_wav_table is array (0 to C_wav_table_len-1) of signed(C_wav_data_bits-1 downto 0);
    function F_wav_table(len: integer; bits: integer)
      return T_wav_table is
        variable i: integer;
        variable y: T_wav_table;
    begin
      for i in 0 to len - 1 loop
        y(i) := to_signed(integer(sin(2.0*3.141592653589793*real(i)/real(len)) * (2.0**real(bits-1)-1.0)), C_wav_data_bits); -- converts sinewave floats to signed number
      end loop;
      return y;
    end F_wav_table;
    constant C_wav_table: T_wav_table := F_wav_table(C_wav_table_len, C_wav_data_bits); -- wave table initializer len, amplitude
    
    -- the data type and initializer for the frequencies table
    constant C_timebase_const_bits: integer := C_timebase_var_bits-C_wav_addr_bits+C_shift_octave; -- bits for timebase addition constants
    constant C_voice_table_len: integer := 2**C_voice_addr_bits;
    type T_freq_table is array (0 to C_voice_table_len-1) of unsigned(C_timebase_const_bits-1 downto 0);
    function F_freq_table(len: integer; temperament: T_halftone_temperament; tones_per_octave: integer;  bits: integer)
      return T_freq_table is
        variable i: integer;
        variable octave, tone: integer;
        variable y: T_freq_table;
    begin
      for i in 0 to len - 1 loop
        octave := i / tones_per_octave; -- octave number
        tone := i mod tones_per_octave; -- tone number
        y(i) := to_unsigned(integer(2.0**(real(octave)+real(temperament(tone)+C_tuning)/1200.0 + real(bits)-real(len)/real(tones_per_octave))), C_timebase_const_bits);
      end loop;
      return y;
    end F_freq_table;
    constant C_freq_table_len: integer := 2**C_timebase_const_bits;
    constant C_freq_table: T_freq_table := F_freq_table(C_voice_table_len, C_halftone_temperament, C_tones_per_octave, C_timebase_const_bits); -- wave table initializer len, freq

    -- the voice volume constant array for testing
    -- replace this ith dual port BRAM where CPU writes and synth reads values
    type T_voice_vol_table is array (0 to C_voice_table_len-1) of signed(C_voice_vol_bits-1 downto 0);
    function F_voice_vol_table(len: integer; bits: integer)
      return T_voice_vol_table is
        variable i: integer;
        variable y: T_voice_vol_table;
    begin
      for i in 0 to len - 1 loop
        -- if i = 1 or i = 2 or i = 3 or i = 4 then -- which voices to enable
        -- if i = 80 then
        -- if i = 7 or i = 21 or i = 22 or i = 23 or i = 24 then -- which voices to enable
        if i = 41 or i = 42 or i = 43 or i = 44 then -- which voices to enable
        -- if i = 115 then -- which voices to enable
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
    signal S_voice_vol, R_voice_vol: signed(C_voice_vol_bits-1 downto 0);
    signal S_wav_data: signed(C_wav_data_bits-1 downto 0);
    signal R_multiplied: signed(C_voice_vol_bits+C_wav_data_bits-1 downto 0);
    signal R_accu: signed(C_accu_bits-1 downto 0);
    signal R_output: signed(C_out_bits-1 downto 0); 
    signal R_led: std_logic_vector(7 downto 0); -- will appear to board LEDs
begin
    -- increment voice number that is currently processed
    process(clk)
    begin
      if rising_edge(clk) then
        R_voice <= R_voice + 1;
        -- if conv_integer(R_voice) = 0 then
          -- R_led <= S_tb_read_data(S_tb_read_data'length-1 downto S_tb_read_data'length-R_led'length);
          -- R_led <= std_logic_vector(S_wav_data(S_wav_data'length-1 downto S_wav_data'length-R_led'length));
          -- R_led <= std_logic_vector(R_multiplied(R_multiplied'length-1 downto R_multiplied'length-R_led'length));
          -- R_led <= std_logic_vector(R_accu(R_accu'length-1 downto R_accu'length-R_led'length));
        -- end if; 
        R_voice_vol <= S_voice_vol; -- simulate 1-clock delay to match BRAM delay
      end if;
    end process;
    -- R_voice contains current address of the voice amplitude and frequency table

    -- increment the time base array in the BRAM
    S_tb_write_data <= S_tb_read_data + to_integer(C_freq_table(conv_integer(R_voice))); -- next time base incremented with frequency
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
    -- waveform data reading (delayed 1 clock, address R_voice-1)
    S_wav_data <= C_wav_table(conv_integer(S_tb_read_data(C_timebase_var_bits-1 downto C_timebase_var_bits-C_wav_addr_bits)));

    -- multiply, store result to register and add register to accumulator
    process(clk)
    begin
      if rising_edge(clk) then
        -- S_voice_vol must be signed, then max amplitude is 2x smaller
        -- count this into designing R_accu large enough to avoid clipping
        -- R_voice_vol used for delay-match with BRAM
        R_multiplied <= R_voice_vol * S_wav_data;
        if conv_integer(R_voice) = 2 then -- output-ready R_accu appears with 2 clocks delay
          R_output <= R_accu(C_accu_bits-1 downto C_accu_bits-C_out_bits);
          R_accu <= (others => '0'); -- reset accumulator
        else
          R_accu <= R_accu + R_multiplied;
        end if;
      end if;
    end process;

    pcm_out <= R_output(R_output'length-1 downto R_output'length-pcm_out'length);
end;

-- todo
-- [ ] shift volume by 1 place, the lowest tone (now 127) should be tone 0
-- [ ] apply 12 meantone temperament using 1200 cents table

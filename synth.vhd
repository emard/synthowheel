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
  C_clk_freq: integer := 25000000; -- Hz system clock
  C_ref_freq: real := 440.0; -- Hz reference tone frequency (usually 440Hz for tone A4)
  C_ref_octave: integer := 5; -- reference octave (default 5)
  C_ref_tone: integer := 9; -- reference tone (default 9, tone A)
  C_voice_addr_bits: integer := 7; -- bits voices (2^n voices, phase accumulators, volume multipliers)
  C_voice_vol_bits: integer := 10; -- bits signed data for volume of each voice
  C_wav_addr_bits: integer := 10;  -- bits unsigned address for wave time base (time resolution)
  C_wav_data_bits: integer := 12; -- bits signed wave amplitude resolution
  C_pa_data_bits: integer := 32; -- bits of data in phase accumulator BRAM
  C_amplify: integer := 0; -- bits louder output but reduces max number of voices by 2^n (clipping)
  C_out_bits: integer := 16 -- bits of signed accumulator data (PCM)
);
port
(
  clk, bus_ce, bus_write: in std_logic;
  bus_addr: in std_logic_vector(1 downto 0);
  bus_byte_sel: in std_logic_vector(3 downto 0);
  bus_in: in std_logic_vector(31 downto 0);
  -- led: out std_logic_vector(7 downto 0);
  pcm_out: out signed(15 downto 0) -- to audio output
);
end;

architecture RTL of synth is
    constant C_tones_per_octave: integer := 12; -- tones per octave
    constant C_cents_per_octave: real := 1200.0; -- cents (tuning) per octave

    -- meantone temperament:
    -- tone cents table f=2^(x/1200), 0-1200 scale for full octave of 12 tones
    type T_meantone_temperament is array (0 to C_tones_per_octave-1) of real;
    -- if temperament starts with C it will match standard MIDI
    -- key numbering (key 0 is C-1, key 69 is A4 (440 Hz), key 127 is G9)

    -- see https://en.wikipedia.org/wiki/Semitone
    -- classical music quarter-comma meantone temperament, chromatic scale
    constant C_quarter_comma_temperament: T_meantone_temperament :=
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

    constant C_equal_temperament: T_meantone_temperament :=
    (
         0.0, --  0 C
       100.0, --  1 C#
       200.0, --  2 D
       300.0, --  3 Eb
       400.0, --  4 E
       500.0, --  5 F
       600.0, --  6 F#
       700.0, --  7 G
       800.0, --  8 G#
       900.0, --  9 A
      1000.0, -- 10 Bb
      1100.0  -- 11 B
    );

    -- Select which temperament to use 
    constant C_temperament: T_meantone_temperament := C_quarter_comma_temperament;

    -- tuning math:
    -- input: C_clk_freq, C_ref_freq, C_ref_octave, C_ref_note, C_pa_data_bits, C_voice_addr_bits
    -- output: C_shift_octave, C_tuning_cents

    -- calculate base frequency, this is lowest possible A, meantone_temperament #9
    constant C_base_freq: real := real(C_clk_freq)*2.0**(C_temperament(C_ref_tone)/C_cents_per_octave-real(C_voice_addr_bits+C_pa_data_bits));
    -- calculate how many octaves (floating point) we need to go up to reach C_ref_freq
    constant C_octave_to_ref: real := log(C_ref_freq/C_base_freq)/log(2.0);
    -- convert real C_octave_to_ref into octave integer and cents tuning
    constant C_shift_octave: integer := integer(C_octave_to_ref)-C_ref_octave;
    constant C_tuning_cents: real := C_cents_per_octave*(C_octave_to_ref-floor(C_octave_to_ref));

    constant C_accu_bits: integer := C_voice_vol_bits+C_wav_data_bits+C_voice_addr_bits-C_amplify-1; -- accumulator register width

    constant C_drawbar_len: integer := 9; -- number of Hammond style drawbars
    type T_drawbar_table is array (0 to C_drawbar_len-1) of real;
    constant C_drawbar_harmonic:   T_drawbar_table := (1.0,3.0, 2.0,4.0,6.0,8.0, 10.0,12.0,16.0);
    -- Hammond common registrations
    constant C_drawbar_sinewave:   T_drawbar_table := (8.0,0.0, 0.0,0.0,0.0,0.0, 0.0,0.0,0.0);
    constant C_drawbar_rockorgan:  T_drawbar_table := (8.0,8.0, 8.0,0.0,0.0,0.0, 0.0,0.0,0.0);
    constant C_drawbar_metalorgan: T_drawbar_table := (8.0,3.0, 1.0,0.0,1.0,0.0, 0.3,0.0,0.0);
    constant C_drawbar_sawtooth:   T_drawbar_table := (8.0,3.0, 4.0,2.0,1.0,1.0, 1.0,0.0,0.0);
    constant C_drawbar_squarewave: T_drawbar_table := (0.0,0.0, 8.0,0.0,3.0,0.0, 2.0,0.0,0.0);
    constant C_drawbar_fullbright: T_drawbar_table := (8.0,8.0, 8.0,8.0,8.0,8.0, 8.0,8.0,8.0);
    -- choose registration
    constant C_drawbar_registration: T_drawbar_table := C_drawbar_metalorgan; -- choose registration

    constant C_wav_table_len: integer := 2**C_wav_addr_bits;
    type T_wav_table is array (0 to C_wav_table_len-1) of signed(C_wav_data_bits-1 downto 0);
    function F_wav_table(len: integer; drawbar_harmonic: T_drawbar_table; drawbar_registration: T_drawbar_table; bits: integer)
      return T_wav_table is
        variable i,j: integer;
        variable w: real; -- omega angular frequency
        variable sum: real; -- sum o wave functions
        variable normalize: real; -- normalize amplitude
        variable y: T_wav_table;
    begin
      normalize := 0.0;
      for j in 0 to drawbar_registration'length-1 loop
        normalize := normalize + drawbar_registration(j);
      end loop;
      for i in 0 to len - 1 loop
        w := 2.0*3.141592653589793*real(i)/real(len); -- w = 2*pi*f
        sum := 0.0;
        for j in 0 to drawbar_registration'length-1 loop
          sum := sum + drawbar_registration(j) * sin(drawbar_harmonic(j)*w);
        end loop;
        y(i) := to_signed(integer( sum/normalize * (2.0**real(bits-1)-1.0)), C_wav_data_bits);
      end loop;
      return y;
    end F_wav_table;
    constant C_wav_table: T_wav_table := F_wav_table(C_wav_table_len, C_drawbar_harmonic, C_drawbar_registration, C_wav_data_bits); -- wave table initializer len, amplitude
    
    -- the data type and initializer for the frequencies table
    constant C_voice_table_len: integer := 2**C_voice_addr_bits;
    constant C_phase_const_bits: integer := C_shift_octave+C_voice_table_len/C_tones_per_octave+2; -- bits for phase accumulator addition constants
    type T_freq_table is array (0 to C_voice_table_len-1) of unsigned(C_phase_const_bits-1 downto 0);
    function F_freq_table(len: integer; temperament: T_meantone_temperament; tuning: real; tones_per_octave: integer; cents_per_octave: real;  bits: integer)
      return T_freq_table is
        variable i: integer;
        variable octave, tone: integer;
        variable y: T_freq_table;
    begin
      for i in 0 to len - 1 loop
        octave := i / tones_per_octave; -- octave number
        tone := i mod tones_per_octave; -- meantone number
        y(i) := to_unsigned(integer(2.0**(real(C_shift_octave+octave)+(temperament(tone)+tuning)/cents_per_octave)+0.5), bits);
      end loop;
      return y;
    end F_freq_table;
    constant C_freq_table: T_freq_table := F_freq_table(C_voice_table_len, C_temperament, C_tuning_cents, C_tones_per_octave, C_cents_per_octave, C_phase_const_bits); -- wave table initializer len, freq

    -- the voice volume constant array for testing
    -- replace this with dual port BRAM where CPU writes and synth reads values
    type T_voice_vol_table is array (0 to C_voice_table_len-1) of signed(C_voice_vol_bits-1 downto 0);
    function F_voice_vol_table(len: integer; bits: integer)
      return T_voice_vol_table is
        variable i,j: integer;
        variable y: T_voice_vol_table;
    begin
      for i in 0 to len - 1 loop
        j := (i-1+len) mod len; -- shift by 1 to match pipeline delay
        -- if i = 0 or i = 1 or i = 2 or i = 3 then -- which voices to enable
        -- if i = 7 or i = 21 or i = 22 or i = 23 or i = 24 then -- which voices to enable
        -- if i = 3*12+0 or i = 3*12+1 or i = 3*12+2 or i = 3*12+3 then -- C3, C#3, D3, Eb3
        -- if i = 3*12+0 or i = 4*12+1 or i = 4*12+3 then -- C3, C#4, Eb4
        -- if i = 0 then -- C-1
        -- if i = 0*12+5 then -- F-1
        -- if i = 3*12+9 then -- A2 (110 Hz)
        -- if i = 4*12+0 then -- C3
        -- if i = 4*12+1 then -- C#3
        -- if i = 4*12+2 then -- D3
        -- if i = 4*12+3 then -- Eb3
        -- if i = 4*12+4 then -- E3
        -- if i = 4*12+5 then -- F3
        -- if i = 4*12+6 then -- F#3
        -- if i = 4*12+7 then -- G3
        -- if i = 4*12+8 then -- G#3
        -- if i = 4*12+9 then -- A3 (220 Hz)
        -- if i = 4*12+10 then -- Bb3
        -- if i = 4*12+11 then -- B3
        if i = 5*12+9 then -- A4 (440 Hz)
        -- if i = 6*12+9 then -- A5 (880 Hz)
        -- if i = 6*12+0 then -- C5
        -- if i = 6*12+9 then -- A5
        -- if i = 127 then -- G9
          y(j) := to_signed(2**(C_voice_vol_bits-1)-1, C_voice_vol_bits); -- one voice max positive volume
        else
          y(j) := to_signed(0, C_voice_vol_bits); -- others muted
        end if;
      end loop;
      return y;
    end F_voice_vol_table;
    constant C_voice_vol_table: T_voice_vol_table := F_voice_vol_table(C_voice_table_len, C_voice_vol_bits); -- vol table for testing
    signal R_voice, S_pa_write_addr: std_logic_vector(C_voice_addr_bits-1 downto 0); -- currently processed voice, destination of increment
    signal S_pa_read_data, S_pa_write_data: std_logic_vector(C_pa_data_bits-1 downto 0); -- current and next phase
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
          -- R_led <= S_pa_read_data(S_pa_read_data'length-1 downto S_pa_read_data'length-R_led'length);
          -- R_led <= std_logic_vector(S_wav_data(S_wav_data'length-1 downto S_wav_data'length-R_led'length));
          -- R_led <= std_logic_vector(R_multiplied(R_multiplied'length-1 downto R_multiplied'length-R_led'length));
          -- R_led <= std_logic_vector(R_accu(R_accu'length-1 downto R_accu'length-R_led'length));
        -- end if; 
        R_voice_vol <= S_voice_vol; -- simulate 1-clock delay to match BRAM delay
      end if;
    end process;
    -- R_voice contains current address of the voice amplitude and frequency table

    -- increment the array of phase accumulators in the BRAM
    S_pa_write_data <= S_pa_read_data + to_integer(C_freq_table(conv_integer(R_voice))); -- next time base incremented with frequency
    -- next value is written on previous address to match register pipeline latency
    S_pa_write_addr <= R_voice - 1;
    phase_accumulator: entity work.bram_true2p_1clk
    generic map
    (
        dual_port => true,
        addr_width => C_voice_addr_bits,
        data_width => C_pa_data_bits
    )
    port map
    (
        clk => clk,
        we_a => '1', -- always write increments
        addr_a => S_pa_write_addr,
        data_in_a => S_pa_write_data,
        we_b => '0', -- always read 
        addr_b => R_voice,
        data_out_b => S_pa_read_data
    );

    -- voice volume reading
    -- get from addressed BRAM the volume of current voice
    S_voice_vol <= C_voice_vol_table(conv_integer(R_voice)); -- connect to bram read output, address R_Voice
    -- waveform data reading (delayed 1 clock, address R_voice-1)
    S_wav_data <= C_wav_table(conv_integer(S_pa_read_data(C_pa_data_bits-1 downto C_pa_data_bits-C_wav_addr_bits)));

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
-- [x] shift volume by 1 place, the lowest tone (now 127) should be tone 0
-- [x] apply 12 meantone temperament using 1200 cents table
-- [x] fix tuning math to work for other than 128 voices
-- [ ] given the max cents error calculate number of phase accumulator bits
-- [ ] f32c CPU bus interface to alter voice amplitudes
-- [ ] bus interface to upload waveforms (or a way of changing drawbar registrations)

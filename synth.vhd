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
generic (
    C_voice_addr_bits: integer := 8; -- 8: 256 voices (counters, volume multipliers)
    C_voice_vol_bits: integer := 16; -- 16: 16-bit signed data for volume
    C_voice_time_bits: integer := 10;  -- 10: 10-bit unsigned data for time base
    C_wav_data_bits: integer := 16;
    C_freq_bits: integer := 32; -- 32 bits for array data of freqs (timebase addition constants)
    C_accu_data: integer := C_freq_bits+C_voice_time_bits; -- good enough accumulator register width
    C_tones_per_octave: integer := 16;
    C_out_data: integer := 16 -- 16-bit of signed accumulator data (PCM)
);
port (
    clk: in std_logic;
    addr: out std_logic_vector(c_addr_bits-1 downto 0); -- memory address
    data: in std_logic_vector(7 downto 0); -- memory data 8 bit
    pcm_out: out signed(15 downto 0) -- to FM transmitter
);
end rds;

architecture RTL of rds is
    constant C_voice_table_len: integer := 2**C_voice_addr_bits;
    constant C_wav_table_len: integer := 2**C_voice_time_bits;
    type T_wav_table is array (0 to C_wav_table_len-1) of signed(C_wav_data_bits-1 downto 0);
    function F_wav_table(len: integer, bits: integer)
      return T_wav_table is
        variable i: integer;
        variable y: T_wav_table
    begin
      for i in 0 to len - 1 loop
        y(i) := to_signed(sin(i*2*3.141592653589793/len)*(2**(bits-1)-1)); -- converts sinewave floats to signed number
      end loop;
      return y;
    end F_wav_table;
    constant C_wav_table: T_wav_table := F_wav_table(C_wav_table_len, C_wav_data_bits); -- wave table initializer len, amplitude
    
    -- the data type and initializer for the frequencies table
    type T_freq_table is array (0 to C_voice_table_len-1) of std_logic_vector(C_freq_bits-1 downto 0);
    function F_freq_table(len: integer, tones_per_octave: integer, bits: integer)
      return T_freq_table is
        variable i: integer;
        variable y: T_freq_table
    begin
      for i in 0 to len - 1 loop
        y(i) := to_unsigned(2**(1.0*i/tones_per_octave) * 2**(bits-1.0*len/tones_per_octave) ); -- converts tuning table floats to signed number
      end loop;
      return y;
    end F_freq_table;
    constant C_freq_table_len: integer := 2**C_freq_bits;
    constant C_freq_table: T_freq_table := F_freq_table(C_voice_table_len, C_tones_per_octave, C_freq_bits); -- wave table initializer len, freq

    signal R_voice, S_tb_inc_addr: std_logic_vector(C_voice_addr_bits-1 downto 0); -- currently processed voice, destination of increment
    signal S_tb_addr_current, S_tb_addr_next: std_logic_vector(C_wav_table_len-1 downto 0); -- current and next timebase
    signal S_tb_rd_vol: signed(C_voice_vol_bits-1 downto 0); -- current volume
    signal S_voice_vol: std_logic_vector(C_voice_vol_bits-1 downto 0);
    signal S_wav_data: signed(C_wav_data-1 downto 0);
    signal R_multiplied: signed(C_voice_vol_bits+C_wav_data_bits-1 downto 0);
    signal R_accu: signed(C_accu_data-1 downto 0);
    signal R_output: signed(C_out_data-1 downto 0);
begin
    -- increment voice number that is currently processed
    process(clk)
    begin
      if rising_edge(clk) then
        R_voice <= R_voice + 1;
      end if;
    end process;
    -- R_voice contains current address of the voice amplitude and frequency table
    
    -- time base increments
    -- increment the time base array (in the BRAM?)
    S_tb_addr_current <= (others => '0'); -- TODO read current timebase from BRAM at R_voice address
    -- next value to be written on previous address
    S_tb_addr_next <= S_tb_addr_current + C_freq_table(R_voice); -- next time base incremented with frequency
    S_tb_inc_addr <= R_voice - 1; -- destination addr is the one before

    -- voice volume reading
    -- get from addressed BRAM the volume of current voice
    S_voice_vol <= (others => '0'); -- connect to bram read output, address R_Voice
    -- waveform data reading
    S_wav_data <= (others => '0'); -- connect to bram timebase read output, address S_tb_addr_current;

    -- multiply it registered and add to accumulator
    process(clk)
    begin
      if rising_edge(clk) then
        R_multiplied <= S_voice_vol * S_wav_data;
        if R_voice = 0 then
          R_output <= R_accu(C_accu_data-1 downto C_accu_data-C_out_data);
          R_accu <= 0; -- reset accumulator
        else
          R_accu <= R_accu + R_multiplied;
        end if;
      end if;
    end process;

end;

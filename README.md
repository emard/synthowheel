# Polyphonic Synth on FPGA

256 independent audio generators which play the same
waveform at different speeds. It is inspired by a set of 
multiple rotating wheels with pickups which may be found in 
Hammond. No intention is made to fully reproduce historic sound,
but rather to produce a mathematically exact polyphonic synth
with FPGA.

In each clock, one of 256 counters (32-bit unsigned) is added to one
of 256 frequencies (32-bit unsigned), providing precise waveform time base
for each of 256 generators. Normally it would be octave-based but
any random tuning is possible.

Upper 10 bits of time base are taken to read 1024-point waveform table data,
obtaining one 16-bit signed waveform value.

In each clock the signed waveform value is hardware-multiplied by one of
256 16-bit volume coefficients and added to 32-bit register.
(every 256 values this register is copied to audio output latch register
and reset to 0 for new cycle of adding).

Generates 48 kHz 16 bit signed output.

This module should listen on a bus and let external CPU (f32c) receive
MIDI commands and update 256 volume coefficients in real time, 
providing a proper sound envelope for each key and make it all behave
like electronic organ or something.

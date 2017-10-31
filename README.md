# Polyphonic Synth on FPGA

True polyphonic synthesizer as paramteric VHDL core with realtime performance.

Array of 128 generators can play the same waveform, either sinewave, or
any other periodic function which describe the sound.
Each generator plays at different speed and volume, numerically 
tuned to octave and 12 halftone temperament, with time base
derived from the stable quartz oscillator.

Polyphonic synthesis is inspired by a set of multiple rotating
[tonewheels](https://en.wikipedia.org/wiki/Tonewheel) with
electromagnetic pickups like found in
[Telharmonium](https://en.wikipedia.org/wiki/Telharmonium) or
[Hammond](https://en.wikipedia.org/wiki/Hammond_organ).
No intention is made to fully reproduce historic sound, but 
to produce a mathematically described polyphonic synth with FPGA.

At each clock cycle, a tuned frequency step is added to one of 128 phase accumulators,
providing precise waveform time base for each generator. Normally it would be 
octave and 12-halftone based but any other tuning is possible.

Upper 10 bits of time base are taken to read 1024-point waveform table data,
obtaining one 16-bit signed waveform value.

In each clock the signed waveform value is hardware-multiplied by one of
128 16-bit volume coefficients and added to 32-bit register.
(every 256 values this register is copied to audio output latch register
and reset to 0 for new cycle of adding).

Generates 48 kHz 16 bit signed output.

This module should listen on a bus and let external CPU (f32c) receive
MIDI commands and update 128 generator volumes in real time, 
providing a proper sound envelope for each key and make it all behave
like electronic organ or something.

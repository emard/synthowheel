# Polyphonic Synth on FPGA

True polyphonic additive synthesizer as paramteric VHDL core with realtime performance.

Array of 128 generators can play the waveform as a weighted
sum of sinewave harmonics, or any user-defined wave function.
Each generator plays at different speed and volume, numerically 
tuned to series of octaves with configurable 12 halftones with
quarter-comma temperament, equal temperament or user-defined temperament
in cents (1/1200).
The time base is derived from the quartz oscillator with relative
stability of 1E-5 so all tones will be stable and correct up to this
value.

Polyphonic synthesis is inspired by a set of multiple rotating
[tonewheels](https://en.wikipedia.org/wiki/Tonewheel) with
electromagnetic pickups like found in
[Hammond organ](https://en.wikipedia.org/wiki/Hammond_organ) which
has a set of drawbars that mix sinewave harmonics to produce characteristic
[tonewheel waveforms](https://www.soundonsound.com/techniques/synthesizing-tonewheel-organs).
No intention is made to fully reproduce historic sound, but 
to produce numerically controled polyphonic synth with FPGA.

At each clock cycle, pre-calculated frequency step is added to a
phase accumulator associated with each voice, providing precise
waveform time base for each generator. The array is 12-halftone based but 
any other tuning is possible.

Upper bits of the phase accumulator are taken to address waveform table data,
obtaining one 16-bit signed waveform value.

In each clock the signed waveform value is multiplied by one of
128 16-bit volume coefficients and added to output accumulator,
which is latched to provide 16-bit 196 kHz PCM from 25 MHz system clock.

At 25 MHz system clock, 32-bit phase accumulator provides max 0.005 cents
tuning error at lowest pitch C0. Higher pitches are more precise,
A4 has 0.0002 cents error. One octave has 1200 cents.

This module should listen on a bus and let external CPU (f32c) receive
MIDI commands and update 128 generator volumes in real time, 
providing a proper sound envelope for each key and make it all behave
like electronic organ or something.

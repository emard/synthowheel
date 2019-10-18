# Polyphonic Synth on FPGA

True polyphonic additive synthesizer as parametric VHDL core with 
realtime performance.

Array of 128 generators simultaneously plays waveform described as a weighted
sum of 9 sinewave harmonics per note. Instead of sinewave, any other user-defined 
wave function can be used.
Each generator plays this waveform at different speed and volume, numerically 
tuned over a full MIDI range of 10+ octaves with configurable meantones with
defaults of quarter-comma, Bach, Hammond, equal temperament or user-defined
temperament in cents (1/1200).
The time base is derived from the quartz oscillator with relative
stability of 1E-5 so all tones will be stable and correct up to this
value.

Polyphonic synthesis is inspired by a set of multiple rotating
[tonewheels](https://en.wikipedia.org/wiki/Tonewheel) with
electromagnetic pickups like found in
[Hammond organ](https://en.wikipedia.org/wiki/Hammond_organ) which
has a set of
[drawbars](http://www.stefanv.com/electronics/hammond_drawbar_science.html)
that mix sinewave harmonics to produce characteristic
[tonewheel waveforms](https://www.soundonsound.com/techniques/synthesizing-tonewheel-organs).
No intention is made to fully reproduce historic sound, but 
to produce numerically controled polyphonic synth with FPGA.

At each clock cycle, pre-calculated frequency step is added to a
phase accumulator associated with each voice, providing precise
waveform time base for each generator. The array is based on
12 meantones per octave but any other tuning is possible.

Upper bits of the phase accumulator are taken to address waveform
table data, reading one 16-bit signed waveform value per clock cycle.

On each clock cycle the signed waveform value is multiplied by 10-bit volume
coefficient from 128 element array and added to output accumulator,
which is latched to provide 16-bit 195 kHz PCM from 25 MHz system clock.

At 25 MHz system clock, 32-bit phase accumulator provides max 0.01 cents
tuning error at lowest pitch C-1. Higher pitches are more precise,
A4 has 0.0002 cents error. One octave has 1200 cents.

# TODO

    [x] Integrate into f32c
    [x] zero-cross volume update (no clicks)

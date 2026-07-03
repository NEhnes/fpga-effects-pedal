#!/usr/bin/env bash

set -e  # stop on first error

# RUN THE FUZZ EFFECT
cd ~/fpga-effects-pedal/testing/src
iverilog -o fuzz_eff_tester.out fuzz_eff_tester.v
vvp fuzz_eff_tester.out

# CONVERT TO WAV
python3 ~/fpga-effects-pedal/testing/scripts/hex24_to_wav.py \
  ../data/fuzz-output.hex ../data/fuzz.wav --rate 48000

# DISPLAY WAVEFORM
python3 ../wave-tui/term_wave.py ../data/fuzz-output.hex

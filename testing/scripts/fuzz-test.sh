#!/usr/bin/env bash

set -e  # stop on first error

# RUN THE FUZZ EFFECT
cd ~/fpga-effects-pedal/testing/src
iverilog -o fuzz_eff_tester.out fuzz_eff_tester.v
vvp fuzz_eff_tester.out

# CONVERT TO WAV
python3 ~/fpga-effects-pedal/testing/scripts/hex24_to_wav.py \
  ../data/hex/fuzz-output.hex ../data/wav/fuzz.wav --rate 48000

# DISPLAY WAVEFORM
python3 ../wave-tui/term_wave.py ../data/hex/fuzz-output.hex ../data/input.hex

# DELETE TEMP FILES
cd ~/fpga-effects-pedal/testing/src
rm fuzz_eff_tester.out

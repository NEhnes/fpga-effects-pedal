#!/usr/bin/env bash

set -e  # stop on first error

# RUN THE FLANGER EFFECT
cd ~/fpga-effects-pedal/testing/src
iverilog -o flanger_eff_tester.out flanger_eff_tester.v
vvp flanger_eff_tester.out

# CONVERT TO WAV
python3 ~/fpga-effects-pedal/testing/scripts/hex24_to_wav.py \
  ../data/hex/flanger-output.hex ../data/wav/flanger.wav --rate 48000

# DISPLAY WAVEFORM
python3 ../wave-tui/term_wave.py ../data/hex/flanger-output.hex ../data/input.hex

# DELETE TEMP FILES
cd ~/fpga-effects-pedal/testing/src
rm flanger_eff_tester.out
rm flanger_eff_tester.vcd

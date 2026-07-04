#!/usr/bin/env bash

set -e  # stop on first error

# RUN THE DELAY EFFECT
cd ~/fpga-effects-pedal/testing/src
iverilog -o delay_eff_tester.out delay_eff_tester.v
vvp delay_eff_tester.out

# CONVERT TO WAV
python3 ~/fpga-effects-pedal/testing/scripts/hex24_to_wav.py \
  ../data/hex/delay-output.hex ../data/wav/delay.wav --rate 48000

# DISPLAY WAVEFORM
python3 ../wave-tui/term_wave.py ../data/hex/delay-output.hex ../data/input.hex

# DELETE TEMP FILES
cd ~/fpga-effects-pedal/testing/src
rm delay_eff_tester.out
rm delay_eff_tester.vcd

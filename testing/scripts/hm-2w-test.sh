#!/usr/bin/env bash

set -e  # stop on first error

# RUN THE FUZZ EFFECT
cd ~/fpga-effects-pedal/testing/src
iverilog -o hm_2w_eff_tester.out hm_2w_eff_tester.v
vvp hm_2w_eff_tester.out

# CONVERT TO WAV
python3 ~/fpga-effects-pedal/testing/scripts/hex24_to_wav.py \
  ../data/hex/hm-2w-output.hex ../data/wav/hm-2w.wav --rate 48000

# DISPLAY WAVEFORM
python3 ../wave-tui/term_wave.py ../data/hex/hm-2w-output.hex ../data/input.hex

# DELETE TEMP FILES
cd ~/fpga-effects-pedal/testing/src
rm hm_2w_eff_tester.out
rm hm_2w_eff_tester.vcd

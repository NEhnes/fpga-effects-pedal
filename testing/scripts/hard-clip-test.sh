#!/usr/bin/env bash

set -e  # stop on first error

# RUN THE HARD CLIP EFFECT
cd ~/fpga-effects-pedal/testing/src
iverilog -o hardclip_eff_tester.out hardclip_eff_tester.v
vvp hardclip_eff_tester.out

# CONVERT TO WAV
python3 ~/fpga-effects-pedal/testing/scripts/hex24_to_wav.py \
  ../data/hex/hard-clip-output.hex ../data/wav/hard-clip.wav --rate 48000

# DISPLAY WAVEFORM
python3 ../wave-tui/term_wave.py ../data/hex/hard-clip-output.hex ../data/input.hex

# DELETE TEMP FILES
cd ~/fpga-effects-pedal/testing/src
rm hardclip_eff_tester.out
rm hardclip_eff_tester.vcd

#!/usr/bin/env bash

set -e  # stop on first error

# RUN THE NOISE GATE EFFECT
cd ~/fpga-effects-pedal/testing/src
iverilog -o noise_gate_eff_tester.out noise_gate_eff_tester.v
vvp noise_gate_eff_tester.out

# CONVERT TO WAV
python3 ~/fpga-effects-pedal/testing/scripts/hex24_to_wav.py \
  ../data/hex/noise-gate-output.hex ../data/wav/noise-gate.wav --rate 48000

# DISPLAY WAVEFORM
python3 ../wave-tui/term_wave.py ../data/hex/noise-gate-output.hex ../data/input.hex

# DELETE TEMP FILES
cd ~/fpga-effects-pedal/testing/src
rm noise_gate_eff_tester.out
rm noise_gate_eff_tester.vcd

#!/usr/bin/env bash
set -e

cd ~/fpga-effects-pedal/testing/src
iverilog -o chorus_eff_tester.out chorus_eff_tester.v
vvp chorus_eff_tester.out

python3 ~/fpga-effects-pedal/testing/scripts/hex24_to_wav.py \
  ../data/hex/chorus-output.hex ../data/wav/chorus.wav --rate 48000

python3 ../wave-tui/term_wave.py ../data/hex/chorus-output.hex ../data/input.hex

rm chorus_eff_tester.out
rm chorus_eff_tester.vcd
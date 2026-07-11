#!/usr/bin/env bash

set -e  # stop on first error

# NAVIGATE TO TB DIRECTORY (ALIAS)
cd ../../tb/eff

# [FAIL] FUZZ -> compiliation issue
iverilog -o fuzz_tb.vvp fuzz_tb.v && vvp fuzz_tb.vvp

# [PASS] DELAY
iverilog -o delay_tb.vvp delay_tb.v && vvp delay_tb.vvp

# [PASS] FLANGER
iverilog -o flanger_tb.vvp flanger_tb.v && vvp flanger_tb.vvp

# [FAIL] HARD CLIP -> missing header, 3/11 failed
iverilog -o hard_clip_tb.vvp hard_clip_tb.v && vvp hard_clip_tb.vvp

# [FAIL] NOISE GATE -> missing header, 9/26 failed
iverilog -o noise_gate_tb.vvp noise_gate_tb.v && vvp noise_gate_tb.vvp

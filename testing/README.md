---
name: testing/README
description: Simulation-driven testing framework for FPGA guitar pedal DSP effects
---

# Testing Framework

This directory contains a self-contained pipeline for running Verilog DSP effect simulations, converting results to playable audio, and visualizing waveforms — all from the terminal. Designed for rapid iteration on guitar effects without needing a hardware FPGA board.

## Directory Layout

```
testing/
├── scripts/           # Shell scripts & Python conversion tools
│   ├── fuzz-test.sh       # Run fuzz effect sim → convert → visualize
│   ├── hard-clip-test.sh  # Run hard-clip effect sim → convert → visualize
│   ├── wav_to_hex24.py    # Convert 24-bit WAV → hex file for $readmemh
│   ├── hex24_to_wav.py    # Convert hex output → playable WAV
│   └── dsp-output.txt     # Quick-reference commands (legacy)
├── src/               # Verilog test bench modules
│   ├── fuzz_eff_tester.v       # Reads input.hex, drives fuzz DUT, writes output
│   ├── hardclip_eff_tester.v   # Same pattern for hard_clip module
│   ├── fuzz_eff_tester.vcd     # Simulation waveform dump (gtkwave)
│   └── hardclip_eff_tester.vcd
├── data/              # Audio data in various formats
│   ├── input.hex            # 200k samples, 24-bit signed hex (mono)
│   ├── input-long.hex       # 720k samples (longer input)
│   ├── funk-guitar-sample.wav  # Source WAV (24-bit, 48 kHz)
│   ├── hex/                 # Processed effect output (.hex)
│   │   ├── fuzz-output.hex
│   │   └── hard-clip-output.hex
│   └── wav/                 # Processed WAV output
│       ├── fuzz.wav
│       └── hard-clip.wav
└── wave-tui/           # Terminal waveform viewer
    └── term_wave.py         # plotext-based dual-waveform plotter
```

## How It Works

Each effect test follows the same flow:

1. **Convert** a 24-bit WAV file to hex (`wav_to_hex24.py`)
2. **Simulate** — Verilog testbench reads hex samples, drives the DSP module via AXI-Stream, writes processed output
3. **Convert back** — `hex24_to_wav.py` turns the result into a playable WAV
4. **Visualize** — `term_wave.py` overlays input vs. output waveforms in the terminal

The testbenches (`fuzz_eff_tester.v`, `hardclip_eff_tester.v`) are self-contained: they generate a 100 MHz clock, handle reset, feed samples cycle-by-cycle, account for pipeline depth, and dump `.vcd` waveforms for GTKWave inspection.

## Running Tests

Run the full pipeline for either effect:

```bash
# Fuzz effect
cd ~/fpga-effects-pedal/testing
bash scripts/fuzz-test.sh

# Hard-clip effect
bash scripts/hard-clip-test.sh
```

Each script: compiles with iverilog, runs the simulation, converts hex output to WAV, launches terminal waveform comparison, then cleans up build artifacts.

To process your own audio, first export as 24-bit signed PCM WAV (48 kHz recommended), then:

```bash
python3 scripts/wav_to_hex24.py my_guitar.wav data/input.hex
```

## Sample Output

### Fuzz Effect

Simulation log:

```
========================================
  FUZZ EFFECT TESTER
========================================
  Module:          fuzz
  pre_gain:        0x7fff (Q1.14)
  pos_clip_thresh: 0x147b (Q0.16)
  neg_clip_thresh: 0x147b (Q0.16)
  tone_coeff:      0xff (0=bright, 255=dark)
  Pipeline:        1 cycles
  Input:           input.hex
  Output:          fuzz-output.hex
========================================
  Read 200000 samples from input.hex
  Wrote 200000 samples to fuzz-output.hex
========================================
  PROCESSING COMPLETE
========================================
```

Hex → WAV conversion:

```
Hex samples: 200000
Channels:    1
Sample rate: 48000 Hz
Frames:      200000
Duration:    4.167 s
Wrote ../data/wav/fuzz.wav
```

Terminal waveform (input in green, fuzz output in blue):

```
                       Dual Waveform Comparison (24-bit signed hex)
          ┌────────────────────────────────────────────────────────────────────┐
 5432574.0┤▞▞ fuzz-output.hex ▀▀▀▀▜   ▛▀▀▀▀▀▀▜            ▐▀▀▀▌    ▛▌▛▀▌▐▀▌▛▀▀│
          │▞▞ input.hex         ▐  ▐       ▐     ▗      ▐   ▌    ▌▌▌ ▌▐ ▌▌  │
          │                   ▌    ▐  ▐       ▐     ▐▖     ▐   ▌    ▌▌▌ ▌▐ █   │
 3621714.7┤                   ▌    ▐  ▐       ▐     ▐▌     ▐   ▌    ▌▌▌ ▌▐ █   │
          │                  ▐     ▐  ▐       ▐     ▐▌     ▐   ▌   ▗▘▌▌ ▌▐ ▜   │
          │                  ▐  ▗▙ ▐  ▐       ▐     ▐▌     ▐   ▌   ▐ ▌▌ ▌▐ ▐   │
 1810855.3┤  ▗▛▀▖            ▐  ▞▐▖ ▌ ▐  ▄▄  ▄ ▐     ▐▌     ▐ ▄ ▌▐▖ ▐ ▌▌ ▌▐ ▗▄▖│
          │ ▗▛  ▚     ▛▙  ▟  ▐▄▟▘ ▙ ▌ ▐        ▐     ▌▌     ▐▞▘▜▌▐▌ ▐▄▌▄▄▌▐▖ ▌ │
      -4.0┤▄▄▄▄▄▄    ▄▄▄▖ ▄  ▗▘   ▝▜▖ ▐▀▘  ▀▀ ▐     ▄▖     ▐  ▝▖▗▖ ▗▘▌▌▘▌▟▝▄▘  │
          │     ▝▀▀▀▀▘  ▀▀▜▖ ▐      ▙ ▐       ▝▄▄▄▖ ▌▜ ▄   ▌   ▀▘▌ ▐ ▜▌ ▀▘     │
          │       ▜  ▐▘  ▐ █▌▗▌      ▝▜▌       ▐   ▌▐▌▌█▀▄▄▄▘   ▌▐▖▛  ▌ ▐▌ ▐▌     │
-1810863.3┤       ▙ ▞   ▝▟▐▀▟▐      ▌ ▐       ▐   ▝█▌▌    ▀ ▐     ▌ ▐▐▌ ▐▌     │
          │       ▝▀▘    █▐  ▐      ▌ ▐       ▐     ▌▐     ▞     ▌ ▐▐▌ ▐▘     │
          │              ▜▐  ▐      ▌ ▐       ▐     ▌▐     ▌     ▌ ▐▐▌        │
-3621722.7┤               ▐  ▐      ▌ ▐       ▝▖    ▌▐     ▌     ▌ ▐▐▌ ▐      │
          │               ▐  ▐      ▌ ▐        ▌    ▌▐     ▌     ▌ ▐▐▌        │
          │               ▐  ▐      ▌ ▐        ▌    ▌▐     ▌     ▌ ▐▐▌        │
-5432582.0┤               ▝▄▄▟      ▐▄▟        ▙▄▟▄▄▌▐▄▄▄▄▄▌     ▚▄▟ ▐▌        │
          └┬────────────────┬────────────────┬───────────────┬────────────────┬┘
         1.0            125.8           250.5          375.2         500.0
Amplitude                              Sample Index
```

### Hard-Clip Effect

Simulation log:

```
========================================
  EFFECT TESTER
========================================
  Module:       hard_clip
  input_gain:   0x7fff (Q1.14)
  norm_clip:    0x4000 (Q0.16)
  Pipeline:     2 cycles
  Input:        input.hex
  Output:       hard-clip-output.hex
========================================
  Read 200000 samples from input.hex
  Wrote 200000 samples to hard-clip-output.hex
========================================
  PROCESSING COMPLETE
========================================
```

Terminal waveform (input in green, hard-clip output in blue):

```
                       Dual Waveform Comparison (24-bit signed hex)
          ┌────────────────────────────────────────────────────────────────────┐
 4194304.0┤▞▞ hard-clip-output.hex    ▗▀▜ ▗▀▌             ▐▀▚             ▛▀▌│
          │▞▞ input.hex              ▐ ▐ ▐ ▌             ▛ ▐       ▗▐    ▌ ▚│
          │                   ▟▞  ▌     ▐ ▐ ▐ ▌             ▌ ▐       ▟▟  ▌ ▌ ▐│
 2796202.7┤                   ▛▌  ▚     ▌ ▝▖▐ ▌            ▗▘ ▐     █ ▛█ ▗▚ ▌ ▝│
          │                   ▌ ▗▙▐▌    ▌  ▙▐ ▐            ▐  ▐     ▌▌▜ ▐▐ ▌  │
          │                   ▌ ▞▐ ▌   ▄▘▄▖▀█ ▐            ▐  ▐     ▌▌▌ ▌▐▐▗▗  │
 1398101.3┤                  ▐ ▗▌ ▌▐  ▐ ▗▛▜ ▘▛▌     ▗      ▐▗▛▙▖   ▐ ▌▌ ▌▐▝▟▛▀▌│
          │                  ▐█▛  ▚▖  ▐ ▞ ▝▄▐ ▚     ▞▖     ▗▛ ▐▌   ▐▄▖▞▟▌▗▙█▌ ▐│
       0.0┤▄▄▄▄▄▄    ▄▄▄▖ ▄  ▗▘    ▜▖ ▐▀▘  ▀▀ ▐     ▟▖     ▐  ▝▌▗▖ ▗▘▌▌ ▌▟▝█▘  │
          │     ▝▀▀▀▀▘  ▀▀▜   ▐      ▙ ▐       ▝▖▄▗  ▌▚ ▖   ▌   ▀▘▌ ▐ ▜▌ ▀▘     │
          │       ▝▀     ▀▐▌ ▌      ▐▄▌       ▐ ▀▘▘▌▐▌▝▄▜   ▌     ▚ ▞ ▚▌ ▐▘     │
-1398101.3┤               ▐▙▗▘      ▌▝▘       ▐  ▗▙▐▌▐▝ ▀▀▟▌     ▝▙▌ ▐▘        │
          │               ▐▝▀▐      ▚ ▞        ▌▟▟▝▀▌▐ ▖   ▌     ▌ ▐ ▐         │
          │               ▐  ▌      ▐ ▌        ▜▌▀▖▐ █   ▌     ▌ ▐           │
-2796202.7┤                ▌ ▌      ▐ ▌           ▌▐ ▗▜   ▌     ▌ ▞           │
          │                ▌ ▌      ▐ ▌           ▌▐  █▐  ▗▘     ▌           │
          │                ▌ ▌      ▝▄▌           ▌▐  █▐  ▐      ▌           │
-4194304.0┤                ▙▄▌       ▝▘           ▙▟  ▝ ▙▄▟      ▐▄▌           │
          └┬────────────────┬────────────────┬───────────────┬────────────────┬┘
         1.0            125.8           250.5          375.2         500.0
Amplitude                              Sample Index
```

## Prerequisites

- [Icarus Verilog](http://iverilog.icarus.com/) (`iverilog` / `vvp`)
- Python 3 with `plotext` (`pip install plotext`)
- Input audio: 24-bit signed PCM WAV, 48 kHz (mono recommended)

## Notes

- Testbench modules `include` effect source from `../../src/eff/` — keep relative paths intact
- The terminal waveform viewer (`term_wave.py`) samples the first 500 points of each file for a quick visual diff
- For detailed waveform inspection, open the `.vcd` files in GTKWave
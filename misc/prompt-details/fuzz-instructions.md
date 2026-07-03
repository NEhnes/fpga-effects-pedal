---
title: Fuzz Effect Design Guidelines
description: Guidelines for implementing a fuzz/distortion effect module for the FPGA guitar pedal project
---

# Fuzz Effect Design Guidelines

This document defines what a fuzz effect is and how to implement it as an AXI-Stream DSP module for the FPGA guitar pedal project.

---

## What is a Fuzz Effect?

A **fuzz effect** is a type of distortion that aggressively clips the input signal, creating a "fuzzy" or "buzzsaw" timbre. Unlike overdrive (soft clipping) or distortion (hard clipping with some rounding), fuzz:

1. **Heavily clips** the waveform into near-square waves
2. **Adds odd/even harmonics** depending on clipping symmetry
3. **Sustains notes** by flattening the waveform peaks
4. **Can be asymmetrical** (different positive/negative thresholds) for unique character

### Classic Fuzz Characteristics

| Characteristic | Implementation Approach |
|---|---|
| Hard clipping | Saturate signal above/below thresholds |
| Asymmetry | Different thresholds for positive/negative |
| Tone control | Simple high-cut filter post-clipping |
| Gain staging | Pre-gain to drive clipping harder |
| Gate/noise gate | Mute below noise floor (optional) |

---

## Architecture Requirements

Follow the **dsp-effect-axi-module-writer** skill. It contains info and a reference template you must use.

---

## Parameterization (Recommended)

Expose these as parameters for hardware tuning:

```verilog
parameter WIDTH = 24,
parameter GAIN_WIDTH = 8,           // Pre-gain control (0-255)
parameter POS_THRESH_WIDTH = 24,    // Positive clip threshold
parameter NEG_THRESH_WIDTH = 24,    // Negative clip threshold
parameter TONE_CUTOFF_WIDTH = 8     // Tone filter coefficient
```

### Runtime Control Options

Option A: **Compile-time parameters** (simpler, fixed hardware)
Option B: **AXI-Lite register interface** (if dynamic control needed)

---

## Core DSP Algorithm

### Basic Hard-Clip Fuzz (Starting Point)

```verilog
// 1. Pre-gain (signed multiplication, keep WIDTH bits)
logic signed [WIDTH:0] gained_sample;  // Extra bit for overflow
assign gained_sample = i_tdata * gain;

// 2. Asymmetric hard clipping
logic signed [WIDTH-1:0] clipped;
always_comb begin
    if (gained_sample > pos_threshold)
        clipped = pos_threshold;
    else if (gained_sample < neg_threshold)
        clipped = neg_threshold;
    else
        clipped = gained_sample[WIDTH-1:0];
end

// 3. Optional: Simple 1-pole lowpass for tone
// y[n] = a * x[n] + (1-a) * y[n-1]
// where a = tone_coefficient (0-1, fixed-point)
```

### Advanced: Germanium-Style Asymmetry

```verilog
// Different clipping curves for positive/negative
// Positive: softer knee (exp/log approximation)
// Negative: harder knee
```

---

## Module Checklist

Before considering the module complete, verify:

- [ ] **Module compiles** with `iverilog -g2012`
- [ ] **Active-low synchronous reset** (`rst_n`) resets all state
- [ ] **No combinational loops** - all state gated by `i_tvalid && o_tready`
- [ ] **Direct backpressure coupling** (`i_tready = o_tready`, `o_tvalid = i_tvalid`)
- [ ] **No internal FIFOs/buffers** - pure combinational DSP in gated block
- [ ] **Signed arithmetic** throughout (24-bit samples are signed)
- [ ] **Parameterized** for hardware flexibility
- [ ] **Testbench exists** (`fuzz_tb.v`) with:
    - [ ] Sine wave input at various amplitudes
    - [ ] Step response (DC input)
    - [ ] VCD waveform output for GTKWave
    - [ ] Verification of clipping behavior

---

## File Placement

```
/home/nehnes/fpga-effects-pedal/sim/fuzz/
├── fuzz.v              # Main module
├── fuzz_tb.v           # Testbench
└── fuzz-instructions.md  # This file
```

---

## Integration with Pipeline

The fuzz module fits in the processing chain:

```
I2S In → [Pre-Gain] → FUZZ → [Tone/Filter] → [Post-Gain] → Delay/Other → I2S Out
```

Downstream modules (delay, etc.) will apply backpressure - your fuzz module must propagate it instantly.

---

## Testing Strategy

1. **Unit test**: `fuzz_tb.v` with known inputs, verify VCD
2. **Integration**: Add to `pipeline.v` and run `pipeline_tb.v`
3. **Hardware**: Synthesize for target FPGA, verify timing closure

---

## Next Steps for Ralph Loop

1. Ralph will read this file and `references/axistream_template.v`
2. Generate `fuzz.v` following these constraints
3. Generate `fuzz_tb.v` following verilog-testbench standards
4. Run simulation, verify waveform
5. Iterate until passing

---

## References
- `sim/hard_clip/hard_clip.v` - Existing hard clip reference
- `dsp-effect-axi-module-writer` skill - Full architectural rules

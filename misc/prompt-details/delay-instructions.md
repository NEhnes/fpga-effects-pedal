# Next Effect Implementation Plan: Digital Delay

## Project Status Assessment

**Current State (based on roadmap checkpoint analysis):**
- ✅ Module 1: Parameterized register/buffer (FIFO buffer exists)
- ✅ Module 2: Fixed-point arithmetic (sub_gain in hard_clip)
- ✅ Module 3: Stream interface with valid/ready (all modules use AXI-Stream pattern)
- ✅ Module 4: First DSP block (hard_clip with gain + clipping)
- ✅ Module 5: Effect chain wrapper (pipeline integrates I2S → FIFO → hard_clip)
- 🎯 **Module 6: Second DSP block (NEXT)** - Targeting weeks 11-12 per roadmap

**Recommendation:** Implement a **Digital Delay Effect** as Module 6.

## Why Digital Delay?

1. **Complementary to hard_clip**: Distortion + Delay are the two most fundamental guitar effect categories
2. **Demonstrates different DSP techniques**: Memory-based processing vs. sample-by-sample math
3. **Uses existing infrastructure**: FIFO buffer pattern already proven, ring buffer logic partially written in delay.v
4. **Resume value**: High - shows ability to implement time-based effects with circular buffers
5. **Roadmap alignment**: "Delay line buffer" explicitly mentioned as Module 6 option

## Implementation Approach

### Architecture Overview

```
Input (AXI-Stream) → [Delay Line: Ring Buffer] → [Mix: Dry + Wet] → Output (AXI-Stream)
                           ↑
                    [Feedback Path] ←←←←←←←←←←←←←←←←←
```

### Key Parameters (all runtime-configurable via AXI-Lite or parameter inputs)

| Parameter | Range | Description |
|-----------|-------|-------------|
| `delay_samples` | 1 - DEPTH | Delay time in samples (48kHz: 1ms = 48 samples) |
| `feedback_q114` | 0 - ~0.99 | Feedback amount (Q1.14 fixed-point) |
| `wet_gain_q114` | 0 - 2.0 | Wet signal gain (Q1.14) |
| `dry_gain_q114` | 0 - 2.0 | Dry signal gain (Q1.14) |
| `input_gain_q114` | 0 - 2.0 | Input gain before delay line (Q1.14) |

### Module Interface

```verilog
module delay_effect #(
    parameter WIDTH = 24,
    parameter DEPTH = 48000  // 1 second at 48kHz
)(
    // Effect parameters (Q1.14 fixed-point unless noted)
    input  wire [15:0] delay_samples,      // Integer: 1 to DEPTH
    input  wire [15:0] feedback_q114,      // Q1.14
    input  wire [15:0] wet_gain_q114,      // Q1.14
    input  wire [15:0] dry_gain_q114,      // Q1.14
    input  wire [15:0] input_gain_q114,    // Q1.14
    
    // AXI-Stream interface
    input  wire        tclk,
    input  wire        rst_n,
    input  wire [WIDTH-1:0] i_tdata,
    input  wire             i_tvalid,
    output wire             i_tready,
    input  wire             o_tready,
    output wire             o_tvalid,
    output reg  [WIDTH-1:0] o_tdata
);
```

### Internal Design

**Ring Buffer:**
- Use existing FIFO-style circular buffer with `write_ptr` and `read_ptr`
- `read_ptr = write_ptr - delay_samples` (with wraparound)
- DEPTH must be power of 2 for efficient modulo via bit masking

**Signal Processing per Sample:**
1. Apply `input_gain` to incoming sample
2. Read delayed sample from ring buffer at `read_ptr`
3. Compute feedback: `delayed_sample * feedback_q114` (with saturation)
4. Write to ring buffer: `input_gained + feedback` (with saturation)
5. Mix output: `dry = input * dry_gain`, `wet = delayed * wet_gain`, `output = dry + wet` (with saturation)
6. Advance `write_ptr`

**Fixed-Point Math (reuse sub_gain pattern):**
- All gains in Q1.14 (1 sign bit, 1 integer bit, 14 fractional)
- Multiplication produces WIDTH+16 bits, round by adding `1 << 13`, shift right 14
- Saturate to WIDTH-bit signed range

### Testbench Strategy

Following the `pipeline_tb.v` pattern:
1. **Reset test**: Verify clean reset behavior
2. **Basic impulse response**: Send single impulse, verify delayed output appears at correct sample
3. **Feedback decay**: Send impulse, verify exponential decay with feedback < 1.0
4. **Parameter sweep**: Test various delay times, feedback amounts
5. **Backpressure handling**: Verify AXI-Stream handshake under `o_tready` stalls
6. **Continuous stream**: Verify sustained operation

### Implementation Steps

1. **Create `sim/delay/delay_effect.v`** - Main module with ring buffer + DSP
2. **Create `sim/delay/delay_effect_tb.v`** - Comprehensive testbench
3. **Add sub-modules if needed** (reuse `sub_gain`, create `sub_mix` for dry/wet)
4. **Run simulation**: `iverilog -g2012 -o delay_effect_tb.out sim/delay/delay_effect.v sim/delay/delay_effect_tb.v`
5. **Verify waveform** in GTKWave
6. **Integrate into pipeline** (optional: create `pipeline_with_delay.v` variant)

### Files to Create/Modify

| File | Action |
|------|--------|
| `sim/delay/delay_effect.v` | NEW - Main delay effect module |
| `sim/delay/delay_effect_tb.v` | NEW - Testbench |
| `sim/pipeline/pipeline_with_delay.v` | OPTIONAL - Pipeline variant with delay |
| `README.md` | UPDATE - Add delay effect to module list |

### Success Criteria (per roadmap Module 6)

- [ ] Module simulates correctly with impulse response test
- [ ] Feedback produces stable decay (no oscillation at feedback < 1.0)
- [ ] All parameters runtime-adjustable without glitches
- [ ] AXI-Stream compliant (handles backpressure correctly)
- [ ] Testbench passes with automated pass/fail reporting
- [ ] VCD waveform shows correct delayed signal timing
- [ ] MATLAB comparison possible (export test vectors for validation)

### Future Extensions (post-MVP)

- **Modulated delay**: LFO on delay time for chorus/flanger
- **Tap tempo**: External clock sync for delay time
- **Multi-tap**: Multiple read pointers for complex echoes
- **Stereo**: Dual-channel with cross-feedback
- **High-pass in feedback loop**: Prevent low-frequency buildup

## Timeline Estimate

| Task | Duration |
|------|----------|
| Design & code delay_effect.v | 1-2 days |
| Write comprehensive testbench | 1 day |
| Simulate, debug, verify | 1-2 days |
| Documentation & integration | 0.5 days |
| **Total** | **3-5 days** |

This fits within the Weeks 11-12 window (Month 3, second half) per the roadmap.

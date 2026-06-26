---
name: Flanger Effect Implementation Guide
description: Step‑by‑step instructions for adding a flanger/chorus module to the FPGA effects‑pedal project
---

# Flanger / Chorus Implementation Guide

This document describes how to add a flanger (or chorus) effect to the **FPGA Effects Pedal** repository. The implementation re‑uses existing Verilog modules (delay line, FIFO buffer, and clocking) and introduces a low‑frequency oscillator (LFO) to modulate the tap position.

## 1. Overview
- **Effect principle**: Mix the original audio signal with a delayed copy whose delay time is periodically modulated by a sinusoidal LFO. The varying delay creates the characteristic “whoosh” (flanger) or subtle thickening (chorus).
- **Key blocks**:
  1. `delay.v` – existing fixed‑delay line.
  2. New `lfo.v` – generates a signed sinusoid (or triangle) at a configurable frequency.
  3. `flanger.v` – combines the original sample with the delay line output at a variable tap determined by the LFO.
- **Resource impact**: Minimal extra LUTs and registers; the LFO can be implemented with a small lookup‑table ROM or a simple accumulator.

## 2. Directory layout
Create a new folder under `sim/`:
```
sim/flanger/
├── flanger.v            # top‑level flanger module
├── flanger_tb.v         # testbench
└── lfo.v                # reusable LFO generator
```
Add the corresponding test‑bench files (see step 5). The module will be referenced from the top‑level `pipeline.v` as an optional effect.

## 3. LFO module (`lfo.v`)
```verilog
module lfo (
    input  wire        clk,
    input  wire        reset,
    input  wire [15:0] freq_ctrl,   // frequency control (e.g., 0‑65535 maps to 0‑10 Hz)
    output reg  [15:0] phase_out    // signed phase output used as delay offset
);
    // Simple N‑bit phase accumulator
    reg [31:0] accum;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            accum <= 32'd0;
            phase_out <= 16'd0;
        end else begin
            accum <= accum + {16'd0, freq_ctrl}; // add frequency control each cycle
            // Take the high 16 bits as a signed sinusoid using a lookup table
            // For a pure triangle LFO you can just use the MSBs directly:
            phase_out <= accum[31:16];
        end
    end
endmodule
```
- **Customization**: Replace the accumulator output with a sine‑lookup‑table ROM for smoother modulation.
- **Frequency range**: Choose `freq_ctrl` such that the resulting frequency is ~0.1 Hz‑10 Hz (typical flanger/chorus speeds).

## 4. Flanger top module (`flanger.v`)
```verilog
module flanger (
    input  wire        clk,
    input  wire        reset,
    input  wire [15:0] audio_in,
    input  wire [15:0] depth,      // max delay offset (samples)
    input  wire [15:0] feedback,
    input  wire [15:0] lfo_freq,
    output wire [15:0] audio_out
);
    // Instantiate LFO
    wire [15:0] lfo_phase;
    lfo u_lfo (
        .clk(clk),
        .reset(reset),
        .freq_ctrl(lfo_freq),
        .phase_out(lfo_phase)
    );

    // Variable‑delay line: reuse existing delay module but expose tap selection
    // Assume delay.v provides a parameterizable length and a `read_addr` input.
    // If not present, add a simple circular buffer with separate read/write pointers.
    wire [15:0] delayed_sample;
    delay #(.MAX_DELAY(4096)) u_delay (
        .clk(clk),
        .reset(reset),
        .sample_in(audio_in),
        // Compute variable tap: base_delay + (lfo_phase * depth) >> 16
        .tap_offset(((lfo_phase * depth) >>> 16)),
        .sample_out(delayed_sample)
    );

    // Mix original and delayed signal with optional feedback
    assign audio_out = audio_in + ((delayed_sample * feedback) >>> 16);
endmodule
```
### Important notes
- **Depth** controls the maximum modulation range (e.g., 0‑200 samples → ~4‑8 ms at 48 kHz).
- **Feedback** adds resonance; keep it ≤ 0.7 to avoid runaway oscillation.
- The `delay` module may need to expose a dynamic `tap_offset` port. If the current implementation only supports a fixed tap, extend it with a simple read‑address calculation as shown.

## 5. Testbench (`flanger_tb.v`)
Create a basic stimulus that feeds a sine‑wave into the flanger and dumps a VCD.
```verilog
`timescale 1ns/1ps
module flanger_tb;
    reg clk = 0;
    always #10 clk = ~clk; // 50 MHz clock (adjust for your design)

    reg reset = 1;
    reg [15:0] audio_in = 0;
    wire [15:0] audio_out;

    // Parameters for the effect
    localparam DEPTH     = 16'd200;   // ~4 ms at 48 kHz
    localparam FEEDBACK  = 16'd8192;  // 0.125 (16'h2000) – scaled Q1.15
    localparam LFO_FREQ  = 16'd5000;  // tune for ~1 Hz

    // Instantiate the flanger
    flanger dut (
        .clk(clk),
        .reset(reset),
        .audio_in(audio_in),
        .depth(DEPTH),
        .feedback(FEEDBACK),
        .lfo_freq(LFO_FREQ),
        .audio_out(audio_out)
    );

    // Generate a 1 kHz audio tone (sampled at 48 kHz)
    integer i;
    always @(posedge clk) begin
        if (reset) begin
            audio_in <= 0;
        end else begin
            audio_in <= $sin(2.0*3.14159*1000.0*i/48000.0) * 32767;
            i <= i + 1;
        end
    end

    initial begin
        $dumpfile("flanger_tb.vcd");
        $dumpvars(0, flanger_tb);
        #100 reset = 0; // release reset after a few cycles
        #500000 $finish; // run for ~10 ms of audio
    end
endmodule
```
- Run with Icarus Verilog as in the README: `iverilog -g2012 -o flanger_tb.out sim/flanger/flanger.v sim/flanger/lfo.v sim/flanger/flanger_tb.v && vvp flanger_tb.out`
- Observe the LFO‑modulated delay in the waveform viewer.

## 6. Integration into the pipeline
1. Open `sim/pipeline/pipeline.v`.
2. Add an instance of `flanger` after the hard‑clip stage (or wherever you prefer).
3. Expose control registers (depth, feedback, lfo_freq) via your existing register interface so the FPGA firmware can tweak the effect in real time.
4. Update the top‑level module’s port list and any documentation.

## 7. Documentation updates
- Add a section **Flanger / Chorus** to `README.md` describing the new effect and how to enable it.
- Create a short usage example in `docs/project_roadmap.md` or a new `docs/flanger.md`.
- Update `project_swot.md` to note the added modulation capability.

## 8. Checklist before committing
- [ ] New modules compile cleanly (`iverilog` on all files).
- [ ] Testbench passes and produces a VCD showing the varying delay.
- [ ] Pipeline integrates without breaking existing effects.
- [ ] README and documentation reflect the new effect.
- [ ] Add the new files to Git (`git add sim/flanger/*`).

Once the checklist is satisfied, commit with a concise message such as:
```
Add flanger/chorus effect module

Implements an LFO‑modulated variable‑delay line, testbench, and integration hooks.
```

---
*End of flanger‑implementation guide.*
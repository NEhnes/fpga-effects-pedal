# Noise Gate — DSP Implementation Guide

A noise gate mutes the signal when its level falls below a threshold, silencing noise during quiet passages.

---

## Signal Flow

```
Input → Envelope Detector → Comparator → Smooth Gain → Makeup Gain → Output
                                  ↑
                             Threshold
```

Three stages:
1. **Envelope detection** — measure the signal's amplitude (peak or RMS follower)
2. **Comparator** — decide whether the gate is open or closed based on threshold
3. **Smooth gain** — apply attack/release ramping to avoid clicks/pops

---

## Parameters

| Param | Width | Description |
|-------|-------|-------------|
| `threshold` | 16-bit Q0.16 unsigned | Level below which the gate closes. Higher = more aggressive gating. |
| `attack` | 16-bit unsigned | How fast the gate opens (in samples). Typical: 0–10000 (~0–200ms @ 48kHz). 0 = instant. |
| `release` | 16-bit unsigned | How fast the gate closes (in samples). Typical: 0–50000 (~0–1s @ 48kHz). 0 = instant. |
| `makeup_gain` | 16-bit Q2.13 signed | Post-gate makeup gain. Unity = `16'd4096`. |

---

## Implementation Notes

### Envelope Detection

Use a simple peak follower with fast-attach/slow-release to approximate signal amplitude:

```verilog
abs_sample = (i_tdata[WIDTH-1]) ? -i_tdata : i_tdata;
envelope   = (abs_sample > envelope) ? abs_sample : envelope - leakage;
```

The `leakage` constant controls the decay rate of the envelope follower. A right-shift works well:

```verilog
wire signed [WIDTH-1:0] leakage = envelope >>> 12; // ~10ms decay @ 48kHz
```

### Comparator

Compare the envelope against the threshold to produce a binary gate signal:

```verilog
wire gate_open = (envelope > scaled_threshold);
```

### Smooth Gain with Attack/Release

Use a counter-based ramp to transition between open (gain ≈ 1.0) and closed (gain ≈ 0.0):

- **Gate opens** (envelope exceeded threshold): increment attack counter toward `attack` value → gain ramps from 0 → 1
- **Gate closes** (envelope below threshold): increment release counter toward `release` value → gain ramps from 1 → 0
- Multiply the sample by the smoothed gain coefficient (Q1.14 fixed-point, same as `sub_gain` in the fuzz example)

### Makeup Gain

Every effect that alters volume **must** include a makeup gain stage at the end. Use the `sub_gain` module from the AXI template — identical to the fuzz example's makeup stage.

---

## Module Template

Conform to the standard AXI-Stream module interface from `axi_template.v`:

```verilog
module noise_gate #(
    parameter WIDTH = 24
)(
    input  wire [15:0] threshold,
    input  wire [15:0] attack,
    input  wire [15:0] release,
    input  wire [15:0] makeup_gain,
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

Direct combinational handshake coupling:
```verilog
assign i_tready = o_tready;
assign o_tvalid = i_tvalid;
```

All internal state updates gated by `if (i_tvalid && o_tready)`.

---

## Key Design Rules (from skill)

1. **No FIFOs or buffers** — backpressure propagates combinationaly
2. **Gated state updates** — every register updates only on `i_tvalid && o_tready`
3. **Makeup gain required** — always include a final makeup gain stage
4. **Keep it combinational** — the envelope follower uses register state, but the gain multiply and comparison are wires

---

## Reference

See the skill's reference files at the paths below for working examples:
- `references/axi_template.v` — module template and handshake discipline
- `references/fuzz_example.v` — completed effect with pre-gain, clipping, tone, and makeup gain stages
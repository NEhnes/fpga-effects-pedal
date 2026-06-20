---
name: FPGA Effects Pedal
description: Overview and usage guide for the FPGA-based guitar effects pedal project
---

# FPGA Effects Pedal

This repository contains a collection of Verilog modules and testbenches for an **FPGA‑based guitar effects pedal**. The focus is on digital signal processing (DSP) blocks that can be synthesized onto an FPGA development board to create real‑time audio effects such as delay, clipping, FIFO buffering, and I²S transceiver handling.

## Directory layout

```
.
├── docs/                # Project documentation and reference material
│   ├── fpga_guitar_pedal_bom.xlsx   # Bill of Materials for the hardware build
│   ├── journal_template.md          # Template for lab / design journals
│   ├── project_context.md           # High‑level project description and goals
│   ├── project_roadmap.md           # Planned milestones and feature roadmap
│   ├── project_swot.md              # Strengths, weaknesses, opportunities, threats
│   └── verilog_skills_tracker.md   # Learning notes for Verilog HDL
│
├── sim/                # Simulation sources and testbenches
│   ├── axistream_template/   # AXI‑Stream interface example
│   │   ├── axistream_template.v
│   │   └── axistream_template_tb.v
│   │   └── txt/… (notes)
│   ├── delay/                # Simple delay line effect
│   │   └── delay.v
│   ├── fifo_buffer/          # FIFO buffer used for sample storage
│   │   ├── fifo_buffer.v
│   │   └── fifo_buffer_tb.v
│   ├── hard_clip/            # Hard clipping distortion module
│   │   ├── hard_clip.v
│   │   └── hard_clip_tb.v
│   ├── i2s_transceiver_in/   # I²S input transceiver (audio codec interface)
│   │   ├── i2s_in.v
│   │   └── i2s_in_tb.v
│   └── pipeline/             # End‑to‑end processing pipeline example
│       ├── pipeline.v
│       └── pipeline_tb.v
└── .claude/                # Claude Code internal metadata (ignore)
```

## Getting started

1. **Prerequisites**
   * A Verilog‑compatible simulator (e.g., Icarus Verilog, ModelSim, or Verilator).
   * (Optional) An FPGA development board that supports the target I/O standards (e.g., Xilinx Artix‑7 or Intel Cyclone V).

2. **Run a simulation**
   ```bash
   # Example: simulate the delay module
   iverilog -g2012 -o delay_tb.out sim/delay/delay.v sim/delay/delay_tb.v
   vvp delay_tb.out
   ```
   Waveforms are generated as `.vcd` files in the same folder (e.g., `delay_tb.vcd`).

3. **Synthesis**
   * Import the desired Verilog files into your FPGA toolchain (Vivado, Quartus, etc.).
   * Map the top‑level module to the board’s I/O pins according to the hardware schematic defined in `docs/fpga_guitar_pedal_bom.xlsx`.

## Contributing

- Add new effect modules under `sim/` with a matching testbench (`*_tb.v`).
- Update documentation in `docs/` whenever you add hardware resources or change the pipeline architecture.
- Keep the `verilog_skills_tracker.md` up‑to‑date with any new language features or design patterns you learn.

## License

This project is provided under the MIT License – see the `LICENSE` file for details.

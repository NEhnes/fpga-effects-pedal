# FPGA Guitar Effects Pedal Project Roadmap (Revised)

## Roadmap Purpose

1. Break the project into manageable chunks that feel achievable over roughly 4 months.
2. Prioritize visible progress and momentum over early perfection.
3. Keep the plan flexible enough for brainstorming while still creating accountability.
4. Emphasize milestones, proof of progress, and resume-worthy outcomes rather than locking into technical details too early.
5. Use MATLAB as a DSP design and verification tool, not as a distraction from the core FPGA build.
6. **Integrate Verilog learning as a foundational, scaffolded track with concrete checkpoint projects tied to the guitar pedal.**

## Roadmap Snapshot

This roadmap is intended for a **first FPGA project** approached by someone who is already technically comfortable, in **electrical engineering**, and capable of learning quickly through structured iteration.

The plan assumes the goal is not to build the final ideal version immediately, but to move from **exploration** to **working prototype** to **presentable project artifact** in steady 1 to 3 week chunks.

MATLAB should support that process by helping with effect modeling, fixed-point validation, coefficient generation, and audio analysis before and after FPGA implementation.

**Verilog learning is front-loaded and scaffolded through small, project-relevant modules that build toward the final guitar pedal DSP blocks.**

## Planning Philosophy

The roadmap is built around a few simple rules:

- Start with progress that reduces uncertainty early.
- Focus on getting something demonstrable working before expanding scope.
- Leave room for pivots, because the project is still in brainstorming mode.
- Treat documentation and demo-readiness as part of the project, not an afterthought.
- Avoid getting trapped in polishing side paths before the core project exists.
- Use MATLAB to prototype and verify DSP ideas before committing them to FPGA logic.
- **Learn Verilog by building real hardware blocks, not in isolation. Each learning checkpoint produces a deliverable that feeds directly into the pedal.**

## Timeline Structure

### Month 1

---

#### Weeks 1 to 2 — Orientation, setup, and Verilog foundations

Primary objective:

- Move from vague idea to committed project direction.
- Establish Verilog familiarity through guided learning and first working module.

Success looks like:

- A clear project definition written in one page or less.
- A chosen baseline platform/tool path.
- A realistic statement of what the first version needs to do.
- A simple personal schedule for when project work will happen each week.
- A MATLAB workspace or project folder set up for DSP modeling and test plots.
- **Icarus Verilog installed and tested with a simple "Hello Hardware" example (counter, OR gate, always block).**
- **First Verilog module written: a parameterized input buffer or register stage (8–16 bits).**
- **Testbench for that module passing in simulation.**

Why this phase matters:

- This prevents wasted time from bouncing between too many possible directions.
- It creates a decision point early, which is especially valuable for a first FPGA project.
- Setting up MATLAB early makes it easy to compare algorithm ideas before hardware work begins.
- **Starting Verilog immediately prevents it from becoming a blocker later. Practicing with testbenches now builds confidence.**

### Deliverables (Weeks 1–2)

- **Project definition document** (< 1 page).
- **Icarus Verilog setup guide** for your machine.
- **First Verilog module:** parameterized register or simple buffer (reusable in pedal).
- **First testbench** using Icarus, demonstrating basic simulation workflow.
- **MATLAB DSP sketch** of one effect idea (e.g., simple gain or filter structure).

---

#### Weeks 3 to 4 — First visible progress and Verilog ramp

Primary objective:

- Reach the first concrete milestone that makes the project feel real.
- Build second Verilog module; practice testbench-driven development.

Success looks like:

- A functioning development workflow (Vivado/Icarus/MATLAB integrated).
- A small but real project artifact that can be shown or discussed.
- A short log of what works, what is confusing, and what still feels risky.
- A basic MATLAB model of one audio effect, filter, or signal chain.
- First plots showing time-domain and frequency-domain behavior of the chosen DSP block.
- **Second Verilog module written: a simple fixed-point adder or multiplier (8×8 or 16×16).**
- **Testbench comparing Verilog output against MATLAB or Python reference.**
- **Simple Vivado project created; proven build flow on target board (even if just blinky LED).**

Why this phase matters:

- Early wins are important for motivation.
- The goal here is confidence, not complexity.
- MATLAB can provide the first "proof of life" for the DSP side before FPGA integration.
- **Writing a second Verilog module with a corresponding reference in MATLAB/Python establishes a testing discipline that will be critical for DSP blocks later.**

### Deliverables (Weeks 3–4)

- **Second Verilog module:** fixed-point arithmetic block with documentation.
- **Testbench with MATLAB reference** showing correctness.
- **Vivado build proof:** board running blinky or simple GPIO test.
- **MATLAB reference model:** one filter or effect structure with plots.
- **Project risk log:** one-pager on biggest unknowns.

---

### Month 2

---

#### Weeks 5 to 6 — Core path commitment and Verilog stream interface

Primary objective:

- Lock in the simplest credible version of the project.
- Practice Verilog I2S stream handling (simpler than full I2S, but realistic).

Success looks like:

- One clearly defined core feature or demonstration target.
- A reduced scope list separating "must-have for version 1" from "interesting later."
- Fewer open-ended decisions floating around in your notes.
- A MATLAB-based reference model for the core effect chain.
- A clear choice of numeric precision strategy, including whether fixed-point is needed in specific blocks.
- **Third Verilog module: a simple stream register or passthrough that handles valid/ready handshaking (AXI Stream lite style).**
- **Testbench with generated waveforms showing stream behavior over time.**
- **One MATLAB coefficient generator script** that produces fixed-point values ready for Verilog parameter or LUT initialization.

Why this phase matters:

- This is where brainstorming turns into execution.
- A smaller finished project is more valuable than a larger half-finished one.
- MATLAB helps prevent committing to an FPGA implementation that sounds good in theory but behaves badly in practice.
- **Learning stream-based interfaces now (before audio DSP) means you won't have to rewrite modules when ADC/DAC Pmods arrive.**

### Deliverables (Weeks 5–6)

- **Project scope document** (v1 feature list and "later" list).
- **Third Verilog module:** stream register with valid/ready control.
- **Testbench showing stream propagation** (can be done in simulation only).
- **MATLAB coefficient export tool** (script that writes fixed-point values to a `.mem` file or Verilog parameter).
- **Numeric precision memo:** chosen bit widths for intermediate stages.

---

#### Weeks 7 to 8 — Build the first meaningful milestone with audio DSP Verilog

Primary objective:

- Achieve a result that proves the project can become real.
- Implement first real DSP block in Verilog (gain or simple filter).

Success looks like:

- One end-to-end path working at a basic level.
- Enough evidence to say the project is no longer just a concept.
- A checkpoint note describing the main blocker to tackle next.
- A MATLAB-to-FPGA comparison path, even if only for one block, such as a filter or gain stage.
- A test vector or reference waveform that can be used to verify hardware behavior.
- **Fourth Verilog module: a fixed-point gain stage or one-pole IIR filter (simple, real audio DSP).**
- **Comprehensive testbench comparing Verilog output sample-by-sample against MATLAB reference data.**
- **Iverilog simulation producing a VCD waveform file viewable in GTKWave.**

Why this phase matters:

- Once an end-to-end path exists, future work becomes iteration instead of speculation.
- MATLAB becomes especially useful here because it gives you a reference against which the FPGA output can be checked.
- **Your first real audio DSP block in Verilog proves you can translate MATLAB math into working hardware logic.**

### Deliverables (Weeks 7–8)

- **Fourth Verilog module:** fixed-point audio DSP block (gain, simple filter, or distortion).
- **Testbench with MATLAB reference vectors** (CSV or binary test data).
- **VCD waveform** showing sample-by-sample behavior.
- **Comparison plot** (MATLAB reference vs. Verilog output overlay).
- **Block documentation** (bit widths, latency, saturation behavior).

---

### Month 3

---

#### Weeks 9 to 10 — Stabilization, repetition, and modular Verilog architecture

Primary objective:

- Make the project repeatable and less fragile.
- Practice Verilog module hierarchy and integration.

Success looks like:

- The main demo can be reproduced consistently.
- Notes and files are organized enough that the project can survive a break in momentum.
- At least one rough demo or screenshot/video-worthy checkpoint exists.
- MATLAB plots or scripts are saved in a repeatable way so the analysis can be rerun later.
- The project includes a simple verification routine comparing expected and actual output.
- **Fifth Verilog module: a simple effect chain wrapper that instantiates and connects multiple smaller blocks (e.g., gain → filter → gain).**
- **Integration testbench** showing multi-block pipeline behavior.
- **Organized Verilog project structure** (separate files for submodules, testbenches, constraint files).

Why this phase matters:

- This is the difference between a lucky breakthrough and an actual project.
- Reliability adds more value than adding flashy extras too early.
- Repeatable MATLAB analysis makes the project easier to debug and easier to present.
- **Writing a hierarchical Verilog design teaches you to think in modules, which is essential for larger systems.**

### Deliverables (Weeks 9–10)

- **Fifth Verilog module:** effect chain or pipeline container.
- **Integration testbench** proving multi-block connection.
- **Organized project directory tree** with clear naming.
- **Repeatable MATLAB verification script** that can regenerate test vectors and plots.
- **Quick-start guide** for re-running the simulation workflow.

---

#### Weeks 11 to 12 — Expansion with restraint and second audio DSP block

Primary objective:

- Add one meaningful improvement without exploding scope.
- Implement a second distinct audio DSP block (different from week 7–8).

Success looks like:

- One additional capability, control path, or workflow improvement is added.
- The original milestone still works after the change.
- A short list exists for what will be intentionally left out of version 1.
- MATLAB is used to test one new effect variation, filter response, or parameter range before hardware changes are made.
- Any new coefficients, tables, or quantization choices are validated in simulation first.
- **Sixth Verilog module: a second audio effect block (e.g., delay line buffer, distortion, modulation operator, or different filter topology).**
- **Testbench comparing this block in isolation and as part of the chain from weeks 9–10.**
- **Parameter set for both blocks documented** (coefficient tables, bit widths, latency in samples).

Why this phase matters:

- This phase gives the project some depth while forcing discipline.
- It keeps momentum high without turning the roadmap into an endless feature list.
- MATLAB helps keep improvements controlled instead of speculative.
- **Building a second effect block proves your Verilog pattern is replicable; you're not a one-trick pony.**

### Deliverables (Weeks 11–12)

- **Sixth Verilog module:** second audio effect block.
- **Standalone testbench** for new block.
- **Updated integration testbench** showing both blocks in sequence.
- **Effect parameter documentation** (latency, coefficient ranges, numeric behavior).
- **Updated scope checklist:** confirm what's in v1, what's deferred.

---

### Month 4

---

#### Weeks 13 to 14 — Demo shaping and hardware integration prep

Primary objective:

- Turn the project from "working for you" into "understandable to someone else."
- Prepare Verilog and testbenches for hardware bring-up.

Success looks like:

- The project can be explained clearly in a few sentences.
- A basic demo flow exists from start to finish.
- The project has enough structure that it can be shown to a recruiter, classmate, or friend without a long apology beforehand.
- MATLAB plots or comparison figures are available to show the DSP design process and results.
- The demo can include a simple visual explanation of the input, processing, and output behavior.
- **Vivado project with synthesized versions of all Verilog modules (targeting Arty Z7-20).**
- **Pre-synthesis testbenches passing on target board (post-place-and-route simulation).**
- **Demo script or checklist** for running testbenches and generating comparison plots.
- **Verilog codebase documented** (module interfaces, timing assumptions, known limitations).

Why this phase matters:

- A strong project is not just built; it is also presentable.
- This is where resume value starts becoming tangible.
- MATLAB outputs can make the project look more engineered and intentional.
- **Synthesized and simulated Verilog on the actual target board proves your design is real, not just simulation magic.**

### Deliverables (Weeks 13–14)

- **Vivado project** with all Verilog modules targeting XC7Z020.
- **Post-synthesis simulation testbench** (proving no unexpected changes in behavior).
- **Demo runbook** (steps to generate test vectors, run simulation, produce comparison plots).
- **Verilog code documentation** (README for each module, timing diagram sketches).
- **Screenshot or waveform gallery** showing testbench results.

---

#### Weeks 15 to 16 — Final packaging, reflection, and roadmap for hardware

Primary objective:

- Finish the 4-month cycle with something complete enough to stand on its own.
- Prepare Verilog codebase for transition to hardware audio I/O.

Success looks like:

- A concise README or project summary is written.
- A small set of images, notes, or demo material is collected.
- The project has a defined "current version" rather than feeling permanently unfinished.
- A next-steps list exists for future improvement, without blocking closure now.
- MATLAB scripts, plots, and reference models are organized well enough that someone else could understand the DSP workflow.
- **Verilog modules fully documented** (block diagrams, timing diagrams, coefficient tables, bit-width analysis).
- **Test vector library organized** (CSV or binary files for repeatable validation).
- **Roadmap for hardware integration drafted** (ADC/DAC Pmod interface Verilog, top-level I2S wrapper, integration plan).
- **GitHub repository (or equivalent) initialized** with clean directory structure and comprehensive README.

Why this phase matters:

- Closure is important.
- A completed version 1 is more motivating and more useful than a project that is always "almost ready."
- A clean MATLAB-assisted workflow makes the project easier to revisit later.
- **A well-documented Verilog codebase is the foundation for hardware bring-up; sloppy documentation now will cost you weeks later.**

### Deliverables (Weeks 15–16)

- **Project README** (overview, module list, simulation instructions, results gallery).
- **Verilog module datasheets** (one doc per block, including interface, latency, constraints).
- **Test vector archive** (organized by module, with generation scripts).
- **MATLAB reference model archive** (all DSP blocks modeled, with plots and comparison data).
- **GitHub/repository** with clean structure and git history.
- **Hardware integration roadmap** (next steps: ADC/DAC interface, I2S wrapper, physical I/O design).

---

## Achievement Gates

These are the main progress checkpoints across the 4 months:

1. **Project direction chosen.**
2. **Development workflow exists (Vivado, Icarus, MATLAB).**
3. **First Verilog module written and simulated.**
4. **First real milestone achieved (DSP block + reference).**
5. **Core version 1 scope locked.**
6. **Basic end-to-end demo works (multi-block Verilog chain in simulation).**
7. **Second audio effect block added and tested.**
8. **Demo and documentation are presentable.**
9. **Version 1 is complete enough to show proudly (Vivado synthesis proven).**

## Verilog Learning Track (Scaffolded Progression)

To ensure Verilog does not become a blocker, learning is scaffolded through six checkpoint modules, each with a testbench and a real purpose in the guitar pedal:

### Module 1 (Weeks 1–2): Input Register / Buffer
- **Purpose:** Learn basic Verilog syntax, parameters, always blocks, testbench structure.
- **Deliverable:** 8–16-bit configurable register; simple testbench.
- **Resume value:** Low (learning exercise), but essential foundation.

### Module 2 (Weeks 3–4): Fixed-Point Arithmetic Unit
- **Purpose:** Learn parameterized modules, bit manipulation, combinational logic.
- **Deliverable:** 8×8 or 16×16 fixed-point multiplier/adder with MATLAB reference.
- **Resume value:** Medium (demonstrates numeric understanding).

### Module 3 (Weeks 5–6): Stream Register (AXI Lite style)
- **Purpose:** Learn valid/ready handshaking, pipeline stages, block-level interfaces.
- **Deliverable:** Stream register with flow-control testbench.
- **Resume value:** Medium (shows you understand hardware streaming).

### Module 4 (Weeks 7–8): First DSP Block (Gain or IIR Filter)
- **Purpose:** Combine modules 1–3 into a real audio effect. Learn integration and waveform verification.
- **Deliverable:** 32-bit audio sample processing with MATLAB comparison.
- **Resume value:** High (real DSP block, production-ready testbench).

### Module 5 (Weeks 9–10): Effect Chain Wrapper
- **Purpose:** Learn module hierarchy, instantiation, port mapping, integration testing.
- **Deliverable:** Multi-block pipeline with organized file structure.
- **Resume value:** Medium–High (shows architectural thinking).

### Module 6 (Weeks 11–12): Second DSP Block (Complementary to Module 4)
- **Purpose:** Prove replicability, deepen DSP knowledge, add distinct capability.
- **Deliverable:** Delay line, distortion, or modulation block; integration with Module 5.
- **Resume value:** High (two independent DSP blocks).

## MATLAB-Specific Gates

To keep MATLAB integrated without letting it take over the project, add these checkpoints:

1. **At least one DSP block modeled in MATLAB.**
2. **At least one fixed-point or quantization check completed.**
3. **At least one FPGA output compared against MATLAB reference data.**
4. **At least one MATLAB plot or figure used in project documentation.**
5. **At least one coefficient, table, or test vector exported from MATLAB into the build workflow.**

## Verilog-Specific Gates

To track Verilog learning and ensure it stays on schedule:

1. **First Verilog module simulates and passes testbench** (Week 2).
2. **Verilog output matches MATLAB reference in numeric block** (Week 4).
3. **Stream interface testbench demonstrates valid/ready handshaking** (Week 6).
4. **First audio DSP block simulates sample-by-sample correctly** (Week 8).
5. **Multi-block Verilog chain simulates end-to-end** (Week 10).
6. **Second DSP block integrated and tested** (Week 12).
7. **All Verilog modules synthesize on target board (Arty Z7-20)** (Week 14).
8. **Testbenches pass post-synthesis simulation** (Week 14).

## Scope Control Notes

To keep the roadmap healthy:

- Delay fancy extras until the core demo exists.
- Do not confuse brainstorming with commitment.
- Avoid resetting the plan every time a cooler idea appears.
- Prefer steady weekly progress over occasional heroic bursts.
- Protect time for documentation, cleanup, and reflection near the end.
- Use MATLAB for support and verification, not as a parallel project that competes with the FPGA build.
- **Do not try to learn Verilog and build audio DSP simultaneously in isolation; tie them together in every module.**
- **A passing testbench is a requirement, not optional; it is the foundation of confidence.**
- **Six Verilog modules by week 12 is the target; it is better to have six simple blocks than one complex block.**

## Verilog Learning Resources (Recommended Quick Reference)

- **Icarus Verilog tutorial:** `iverilog` command-line workflow, `.v` file organization.
- **Testbench patterns:** basic `$display`, `$monitor`, file I/O (`$readmemb`, `$writememb`).
- **GTKWave:** VCD file inspection for waveform debugging.
- **Vivado synthesis:** pragmas for inferring multipliers, adders, block RAM (BRAM).
- **Fixed-point math in Verilog:** bit-width tracking, rounding, saturation.
- **AXI Stream introduction:** valid/ready handshaking, tuser/tkeep signals (basic familiarity, not full mastery).

Resources can be added as you discover them; this is not a comprehensive syllabus.

## One-paragraph compressed version

This revised 4-month roadmap takes a first-time FPGA project from brainstorming to a presentable version 1 by scaffolding Verilog learning through six checkpoint modules, each with a real purpose in the guitar pedal and a corresponding testbench that ties to MATLAB reference models. Weeks 1–2 establish Icarus and Vivado workflows with a simple register; weeks 3–4 add fixed-point arithmetic; weeks 5–6 introduce stream interfaces; weeks 7–8 deliver the first real audio DSP block; weeks 9–10 build a multi-block pipeline; weeks 11–12 add a second effect; and weeks 13–16 finalize documentation, synthesis, and a hardware integration roadmap. Each module is tested against MATLAB or Python reference data before integration, building confidence and resume-worthy artifacts incrementally. Verilog learning is not deferred; it is front-loaded and made concrete through project-relevant deliverables.
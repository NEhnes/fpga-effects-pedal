# Verilog Skills Tracker – FPGA Guitar Effects Pedal

Track your progress through the core Verilog skills needed for the 4-month roadmap.

---

## Syntax & Structure

### Module Basics
- [x] Module definition, parameters, ports (input/output/inout)
  - Date learned: May 18

- [ ] Parameterized modules (defparam, parameter declarations)
  - Date learned: ______________

- [x] Port declarations and port mapping in instantiation
  - Date learned: May 18

### Data Types & Variables
- [x] Wire, reg, and logic declarations
  - Date learned: May 18

- [x] Bit-width declarations and vector indexing
  - Date learned: May 18

- [ ] Signed vs. unsigned operations
  - Date learned: ______________

### Control Structures
- [ ] Always blocks: combinational (`always @(*)`)
  - Date learned: ____________

- [x] Always blocks: sequential (`always @(posedge clk)`)
  - Date learned: May 20

- [ ] Always blocks: latches and sensitivity lists
  - Date learned: ______________

- [x] If/else, case statements
  - Date learned: May 20

### Operators
- [x] Arithmetic operators (+, -, *, /)
  - Date learned: May 20

- [x] Bitwise operators (&, |, ^, ~)
  - Date learned: May 18

- [x] Shift operators (<<, >>)
  - Date learned: May 23

- [x] Ternary operator (?:)
  - Date learned: May 20

---

## Testbenches

### Basic Testbench Structure
- [x] Writing a testbench module (no ports)
  - Date learned: May 18

- [x] Initial blocks for stimulus generation
  - Date learned: May 18

- [x] Clock generation and reset sequencing
  - Date learned: May 18

- [x] Time delay and `#` timing directives
  - Date learned: May 18

### Debugging & Output
- [x] `$display` and `$write` for console output
  - Date learned: May 20

- [ ] `$monitor` for continuous signal tracking
  - Date learned: ______________

- [x] `$finish` to end simulation gracefully
  - Date learned: May 20

### File I/O & Test Vectors
- [x] `$readmemb` to load binary test data
  - Date learned: May 23

- [x] `$readmemh` to load hex test data
  - Date learned: May 23

- [ ] `$writememb` to save test results
  - Date learned: ______________

- [x] File output with `$fopen`, `$fwrite`
  - Date learned: May 23

### Waveform Inspection
- [x] Generating VCD files (dump statements)
  - Date learned: May 18

- [x] `$dumpvars` for selective signal capture
  - Date learned: May 18

- [x] Viewing VCD in GTKWave
  - Date learned: May 18

---

## Hardware Design Patterns

### Module Instantiation & Hierarchy
- [x] Instantiating submodules in a parent module
  - Date learned: May 18

- [x] Port mapping (named and positional)
  - Date learned: May 18

- [x] Hierarchical module organization
  - Date learned: May 20

### Pipeline Design
- [x] Creating pipeline stages with intermediate registers
  - Date learned: May 23

- [ ] Understanding latency vs. throughput
  - Date learned: ______________

- [ ] Data and control signal propagation through stages
  - Date learned: ______________

### Handshaking & Flow Control
- [ ] Valid/ready signaling basics
  - Date learned: ______________

- [ ] Implementing a valid/ready register stage
  - Date learned: ______________

- [ ] Stalling and back-pressure handling
  - Date learned: ______________

- [ ] AXI Stream lite protocol (basic familiarity)
  - Date learned: ______________

### Clock & Reset
- [ ] Synchronous reset assertion and deassertion
  - Date learned: ______________

- [ ] Reset distribution in multi-module designs
  - Date learned: ______________

- [ ] Clock domain basics (single domain, intro to CDC)
  - Date learned: ______________

---

## Numeric Design

### Fixed-Point Arithmetic
- [x] Understanding fixed-point representation
  - Date learned: May 23

- [x] Bit-width calculations for products and sums
  - Date learned: May 23

- [x] Scaling and shifting for fixed-point operations
  - Date learned: May 23

- [x] Rounding and truncation in fixed-point
  - Date learned: May 23

### Saturation & Overflow
- [ ] Detecting overflow conditions
  - Date learned: ______________

- [x] Implementing saturation logic
  - Date learned: May 23

- [ ] Wrapping vs. saturating behavior
  - Date learned: ______________

### Parameterized Arithmetic
- [ ] Writing generic multipliers and adders with parameters
  - Date learned: ______________

- [ ] Bit-width propagation through parameterized modules
  - Date learned: ______________

- [ ] MATLAB/Python reference modeling for numeric validation
  - Date learned: ______________

---

## Integration & System Design

### Module Hierarchy
- [ ] Creating a wrapper or top-level module
  - Date learned: ______________

- [x] Connecting multiple submodules in sequence (pipeline)
  - Date learned: May 21

- [ ] Managing port fan-out and naming consistency
  - Date learned: ______________

### Audio DSP Specifics
- [x] Structuring a gain stage module
  - Date learned: May 21

- [x] Building a simple FIR filter in hardware
  - Date learned: May 25

- [ ] Understanding latency in DSP blocks
  - Date learned: ______________

- [ ] Coefficient storage (parameters, ROM, BRAM)
  - Date learned: ______________

### System-Level Thinking
- [ ] Defining clear module interfaces
  - Date learned: ______________

- [ ] Documenting assumptions (bit widths, timing, latency)
  - Date learned: ______________

- [ ] Planning for testability in larger designs
  - Date learned: ______________

---

## Synthesis & Tool-Specific

### Icarus Verilog
- [x] Running `iverilog` from command line
  - Date learned: May 18

- [x] Compiling and running simulations
  - Date learned: May 18

- [ ] Debugging with `-g` flag and GTKWave
  - Date learned: ______________

### Vivado Synthesis
- [ ] Creating a new Vivado project and adding Verilog files
  - Date learned: ______________

- [ ] Running synthesis and viewing reports
  - Date learned: ______________

- [ ] Recognizing inferred vs. explicit resources (multipliers, adders, BRAM)
  - Date learned: ______________

- [ ] Constraint files (XDC) for timing and I/O
  - Date learned: ______________

### Implementation & Place & Route
- [ ] Running place and route in Vivado
  - Date learned: ______________

- [ ] Interpreting timing reports
  - Date learned: ______________

- [ ] Post-synthesis and post-PAR simulation
  - Date learned: ______________

---

## Verification & Testing

### Testbench Patterns
- [ ] Writing reusable testbench modules
  - Date learned: ______________

- [ ] Test vector generation (manual and scripted)
  - Date learned: ______________

- [ ] Assertion-based checking
  - Date learned: ______________

### Comparison Against Reference
- [ ] Loading test vectors from MATLAB/Python CSV or binary
  - Date learned: ______________

- [ ] Sample-by-sample output comparison in testbench
  - Date learned: ______________

- [ ] Error reporting and debugging mismatches
  - Date learned: ______________

### Waveform Analysis
- [x] Inspecting timing in GTKWave
  - Date learned: May 18

- [ ] Measuring signal latency and propagation
  - Date learned: ______________

- [ ] Verifying control signal sequences
  - Date learned: ______________

---

## Checkpoint Milestones (Roadmap-Aligned)

Track when you complete each module's Verilog milestone:

### Module 1 – Input Register (Weeks 1–2)
- [ ] 8–16-bit register module written
  - Date completed: ______________
- [ ] Simple testbench written and passing
  - Date completed: ______________

### Module 2 – Fixed-Point Arithmetic (Weeks 3–4)
- [ ] 8×8 or 16×16 multiplier/adder module written
  - Date completed: ______________
- [ ] Testbench comparing against MATLAB reference
  - Date completed: ______________

### Module 3 – Stream Register (Weeks 5–6)
- [ ] Valid/ready stream register module written
  - Date completed: ______________
- [ ] Flow-control testbench passing
  - Date completed: ______________

### Module 4 – First DSP Block (Weeks 7–8)
- [ ] Gain or simple IIR filter module written
  - Date completed: ______________
- [ ] Comprehensive testbench with MATLAB reference vectors
  - Date completed: ______________
- [ ] VCD waveform generated and inspected
  - Date completed: ______________

### Module 5 – Effect Chain Wrapper (Weeks 9–10)
- [ ] Multi-block pipeline module written
  - Date completed: ______________
- [ ] Integration testbench passing
  - Date completed: ______________
- [ ] Organized project directory structure
  - Date completed: ______________

### Module 6 – Second DSP Block (Weeks 11–12)
- [ ] Delay, distortion, or modulation module written
  - Date completed: ______________
- [ ] Standalone testbench passing
  - Date completed: ______________
- [ ] Integrated with Module 5 and tested
  - Date completed: ______________

### Synthesis & Verification (Weeks 13–14)
- [ ] All modules synthesize in Vivado
  - Date completed: ______________
- [ ] Post-synthesis simulation testbenches pass
  - Date completed: ______________

---

## Notes & Reflections

Use this section to capture insights as you learn:

### Challenging Concepts
- 
- 
- 

### Breakthroughs & Aha Moments
- 
- 
- 

### Resources That Helped
- 
- 
- 

### Personal Roadblocks & How You Solved Them
- 
- 
- 

---

## Quick Reference: Verilog Reminders

**Always use testbenches.** A passing testbench is not optional; it's your confidence foundation.

**Tie Verilog to MATLAB.** Every numeric block should have a MATLAB reference or comparison.

**Learn by doing.** Build the six checkpoint modules in order; don't try to master Verilog in isolation.

**Document as you go.** Bit widths, latencies, and assumptions matter; write them down immediately.

**Keep it simple.** Six simple Verilog blocks are better than one complex block. Iteration beats perfection.

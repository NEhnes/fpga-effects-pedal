# FPGA Guitar Effects Pedal Project Context

## Project Purpose

1. Look good on a resume for co-op applications (targeting embedded, DSP, robotics roles in humanoid robotics, space & defense tech, automation)
2. Enjoy building some really cool shit and provide entertainment/purpose during a summer at a dull co-op office job
3. Rekindle my past hobby of playing guitar

## Project Snapshot

This project is an **FPGA-based guitar effects pedal** built around an **SoC** dev board. An FPGA-oriented design was chosen for 3 key reasons:
1. FPGA design allows for rapid reconfiguration and resequencing of effects not possible with analog effect pedals.
2. Cost-effective way to access theoretically infinite pedals; the cost of physical pedals adds up fast
3. Provides a practical way to reconfigure effect chains in short period of time without a tangle of cables

## Data Flow

[Guitar Pickups]
       │
  (Analog AC)  <-- Low voltage (~100mV - 1Vpp), High Impedance (High-Z)
       ▼
[Pre-Amp / Op-Amp Stage]
       │
 (Analog AC + DC Bias)  <-- Lifted to a 1.65V DC offset to prevent negative voltage rail clipping
       ▼
[ADC Pmod]
       │
     (I2S)  <-- Digital Serial Stream: BCLK, LRCLK, SDOUT
       ▼
[FPGA Fabric]  <-- Real-time hardware DSP algorithms (Distortion, Delay, Modulation)
       │
     (I2S)  <-- Processed Digital Serial Stream: BCLK, LRCLK, SDIN
       ▼
[DAC Pmod]
       │
 (Analog + DC Bias)  <-- Smooths digital steps; still riding on 1.65V DC offset
       ▼
[LPF & AC-Coupling Cap]
       │
  (Analog AC)  <-- Low-pass filter removes high-frequency clock noise; Cap strips the 1.65V DC bias
       ▼
[Output Amplifier]  <-- Pure, safe Analog AC signal centered back around 0V ground

## Primary Goals

- Build a working prototype of a **digital guitar pedal** with FPGA-based effects processing.
- Use a **SoC FPGA** rather than a plain FPGA so Linux can handle effect management, UI logic, and preset/effect-chain control.
- Support **modular effect blocks** connected using **AXI stream**, likely with a switch/crossbar architecture for reconfigurable effect chains.
- Make the system suitable for **effect switching**, **custom effect sequences**, and future experimentation with more advanced DSP routing.
- Design **AI-assisted workflow** so that non-technical users can create custom effects with less work.

## Current Architecture Direction

### Core processing platform

The current preferred FPGA platform is the **Digilent Arty Z7-20**, because it provides a Zynq-7000 SoC with the **XC7Z020** device, offering substantially more FPGA resources than the smaller Z7-10 variant.

Why this board is currently favored:

- Dual-core ARM Cortex-A9 processing system for Linux/PetaLinux workflows.
- FPGA fabric large enough for multiple DSP/effect blocks and routing logic.
- Pmod connectivity for faster ADC/DAC bring-up.
- Easier path for prototyping than jumping immediately to a more complex Zynq UltraScale+ platform.
- Reasonable (ish) price after Digilent student discount.

### Audio path

Current audio I/O plan:

- **Input ADC:** Digilent **Pmod AD1**, a two-channel 12-bit ADC Pmod.
- **Output DAC:** Digilent **Pmod DA3**, a 16-bit DAC Pmod.

This choice is mainly about reducing bring-up complexity and leveraging readily available modules with existing documentation and known interfaces.

### Software / control split

Planned split of responsibilities:

- **FPGA fabric (PL):** real-time audio DSP, stream routing, effect modules, crossbar/switching logic.
- **ARM/Linux side (PS):** UI, preset management, effect ordering, possibly patch storage and higher-level orchestration.
- **PetaLinux:** intended OS environment for the Linux side.

## UI Direction

The project currently values **ease of programming as a Linux peripheral** more than having a fancy embedded UI immediately. A simple terminal UI would suffice to start. UI is **not** a top priority as I can see it being a time sink that provides less value as a resume piece.

UI will start as a simple terminal app (either on my laptop over a port, or locally). If not, something easier. Onboard GUI/HUD will be reserved for the very end of project, as it is not key to establishing my DSP/FPGA chops.

### Most practical UI approaches under consideration

#### 1. Laptop-hosted UI

A host-side UI running on a laptop is considered the easiest prototyping path. The pedal can expose a control interface over USB serial or Ethernet, while a browser app or desktop app handles deeper editing and configuration.

Why this is attractive:

- Fastest iteration loop.
- Avoids early time sink in embedded Linux display/UI plumbing.
- Good for debugging presets, routing, and internal state.
- Can be ported over to SoC system at a later date.

#### 2. Helper MCU over USB serial

A small microcontroller can handle local controls such as encoder/buttons/display and communicate with Linux over USB CDC serial.

This is attractive because it keeps Linux-side software simple while offloading debounce, encoder decoding, display refresh, and local control scanning. I am also more familiar with microcontrollers than embedded Linux & FPGA environments.

#### 3. USB HID control surface

A USB HID-based control interface such as a rotary encoder/macropad/footswitch is another option because Linux can treat it as standard input without a custom kernel driver in many cases.

#### 4. HDMI + USB touchscreen

This remains possible, especially for a richer embedded UI, but is seen as heavier in mechanical complexity and probably not the best first version. This would be **after** the project is essentailly complete and fully documented.

## Potential Control Hardware

FILL OUT LATER. POTENTIOMETERS, DIALS, FOOT PRESS BUTTON, ETC ETC

## Test and debug philosophy

### Oscilloscope status

An oscilloscope is **not considered strictly necessary** for the first version of this project.

The preliminary view is that most project risk is in:

- audio quality,
- DSP correctness,
- routing behavior,
- peripheral communications,

rather than in high-speed analog or RF debugging.

### Audio analysis preference

A **USB audio analyzer** or even a **USB audio interface plus software tools** is viewed as more valuable than a general oscilloscope for this specific project, because the pedal is fundamentally an audio product.

Useful measurements include:

- frequency response,
- noise floor,
- THD+N,
- clipping behavior,
- impulse response,
- effect coloration.

### Logic analyzer status

A **24 MHz USB logic analyzer** is likely sufficient for this project’s expected digital-debug needs, especially for:

- SPI to ADC/DAC,
- I2C to a small display,
- GPIO,
- encoder/button signals,
- basic peripheral bring-up.

It is **not** intended for high-speed internal FPGA clocks or DDR-level debug, but that is acceptable because internal FPGA debugging can be handled with tools like Vivado ILA instead.

## Design assumptions and constraints

### Functional assumptions

- Mono guitar pedal is acceptable for the first revision.
- Linux is being used mainly for control/UI rather than time-critical DSP.
- Real-time audio DSP should remain in FPGA fabric rather than Linux userspace.
- Modular routing is a key project goal, not just a single fixed effect.

### Practical assumptions

- Canadian pricing and sourcing matter (seek student discount if possible).
- Readily available dev boards and modules are preferred over fully custom hardware for the first version.
- Ease of bring-up matters more than perfect optimization at this stage.
- It is acceptable to prototype with external UI hardware or a laptop before converging on a final enclosure-integrated UI.

## Current hardware direction

### Current likely platform components

- **Main board:** Digilent Arty Z7-20 (Zynq-7000 SoC, XC7Z020).
- **ADC:** Digilent Pmod AD1.
- **DAC:** Digilent Pmod DA3.
- **Primary UI control:** Rotary encoder & buttons
- **Optional local display:** small OLED or similar low-complexity display.
- **Debug tools:** multimeter, 24 MHz logic analyzer, Vivado design suite, and audio-analysis setup.

### Possible supporting hardware

- Footswitches for bypass/preset/tap functions.
- 1/4 inch input/output jacks.
- 9V pedal power input with local regulation.
- Enclosure sized more like a larger digital stompbox than a minimal analog pedal if onboard UI grows.

## AXI-Stream Effect Module Design

### Passthrough Template (All Effects Use This)

```verilog
module passthrough #(parameter WIDTH = 24)(
    input  wire tclk, rst_n,
    input  wire [WIDTH-1:0] i_tdata,
    input  wire i_tvalid,
    output wire i_tready,
    input  wire o_tready,
    output wire o_tvalid,
    output reg [WIDTH-1:0] o_tdata
);

assign i_tready = o_tready;        // Backpressure propagation
assign o_tvalid = i_tvalid;        // Forward signaling
always @(posedge tclk or negedge rst_n) begin
    if (!rst_n) o_tdata <= {WIDTH{1'b0}};
    else if (i_tvalid && i_tready) o_tdata <= i_tdata;
end
endmodule
```

**Compliance:** Handshake-driven transfers ($i_{tvalid} \land i_{tready}$), backpressure chains correctly, data stable. **Works at any pipeline position.**

**Timing risk:** Combinational path $o_{tready} \to i_{tready}$ across multiple effects. **Mitigation if synthesis fails:** register $i_{tready}$ output (adds $1 \times tclk$ to backpressure propagation—imperceptible for audio).

### Effect Chain Data Flow

```
ADC Pmod -I2S-> I2S RX -AXI-> FIFO -AXI-> [Effect1, Effect2, Effect3] -AXI-> I2S TX -I2S-> DAC Pmod
```

Each effect is identical template; plug/unplug without modification.

## Open technical questions

1. **Audio sample rate** and internal processing clock.
2. **Sample-by-sample vs. frame-based** DSP.
3. **Crossbar topology** for dynamic effect reordering (fixed chains vs. runtime switching).
4. Pmod ADC/DAC vs. codec migration path.
5. Power distribution for clean audio.
6. **Preset serialization** (JSON, binary, where stored).
7. Pre-DAC buffer/preamp specs.
8. **Parameter control interface:** AXI-Lite registers? AXI-Stream sideband? How does Linux adjust effect knobs?

## Recommended framing for future LLM assistance

When using this project description with another LLM, the most useful assumption set is:

- Treat this as a **hybrid FPGA + embedded Linux audio product**.
- Assume **Zynq-7000 SoC (Arty Z7-20 / XC7Z020)** unless explicitly changed.
- Assume **ADC Pmod in, FPGA DSP, DAC Pmod out** as the current baseline hardware architecture.
- Assume the user is interested in **modular real-time DSP blocks**, **AXI Stream routing**, and **Linux-based control/UI**.
- Prefer **practical prototype advice** over ideal but expensive/complex solutions.
- Prefer **simple bring-up paths** and **debuggable architectures**.
- Consider **laptop UI or helper-MCU UI** as valid and desirable early-stage options.
- Treat **audio testing quality** as more important than generic bench-instrument prestige.

## One-paragraph compressed version

A guitar effects pedal is being planned around a Digilent Arty Z7-20 Zynq-7000 SoC board using the XC7Z020, with audio entering via a Pmod ADC and leaving via a Pmod DAC. The FPGA fabric is intended to run modular real-time DSP effect blocks connected through AXI Stream-style routing/crossbar logic, while PetaLinux on the ARM side handles UI, presets, and effect-chain control. The current preference is for a practical, easy-to-debug prototype: likely a rotary-encoder-based or laptop-hosted UI, a 24 MHz USB logic analyzer for digital bring-up, and an audio analyzer or USB audio interface for testing instead of advanced, expensive tools like an oscilloscope.
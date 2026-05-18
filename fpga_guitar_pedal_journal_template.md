# FPGA Guitar Pedal—Weekly Journal

**Week [#] | Phase [Setup/MVP/Expand/Polish] | [Start Date] – [End Date]**

---

## Raw Notes
*Unstructured—whatever you captured per session. AI will aggregate.*


## Weekly Summary
*AI-formatted. Covers work, learning, decisions.*

### Overview
| Item | Value |
|------|-------|
| **Phase** | Setup / MVP / Expand / Polish |
| **Primary goal** | [One line] |
| **Status** | On track / Delayed / Blocked |
| **Total hours** | |
| **Main deliverable** | |

---

### Work Completed

| Area | What Happened | Outcome |
|------|---------------|---------|
| **Analog** | e.g., "Designed preamp, simulated in LTspice" | 20 dB gain, $f_c = 20$ kHz ±0.3 dB |
| **Verilog/Synthesis** | e.g., "Coded ADC I2S RX module" | Behavioral sim passes, 4% slice util |
| **Peripheral test** | e.g., "Verified Pmod AD1 timing" | Logic analyzer: BCLK/LRCLK clean |
| **DSP algorithm** | e.g., "Implemented soft-clip distortion" | No arithmetic overflow, THD~2% |
| **Integration** | e.g., "Wired ADC → FPGA → DAC chain" | End-to-end audio pass-through OK |
| **Debug** | e.g., "Found I2S frame shift bug" | Root: inverted BCLK polarity in XDC |
| **Testing/validation** | e.g., "Recorded frequency response" | 20 Hz–20 kHz, ±2 dB flat |

---

### Problem-Solving
**Problem**: [What broke / didn't work]  
**Approach**: [What you tried]  
**Resolution**: [What actually fixed it]  
**Lesson**: [One sentence takeaway for future]

---

### Learning Gaps Filled
| Gap | Resource | Time | Takeaway |
|-----|----------|------|----------|
| e.g., "I2S protocol details" | Datasheet + GitHub examples | 2h | Frame sync critical; BCLK polarity matters |
| e.g., "Fixed-point arithmetic" | TI app note + testing | 1.5h | Saturation arith safer than wrapping |

---

## Design Decisions

### Architecture Decision
**Context**: [What you were building]  
**Question**: [What choice did you face?]  
**Options**:
- Option A: [approach] — Pro: [+] Con: [−]
- Option B: [approach] — Pro: [+] Con: [−]

**Decision**: Option [X]  
**Rationale**: [1–2 sentences why]  
**Trade-off accepted**: [What you gave up]  
**Confidence**: High / Medium / Low  

---

### Parameter Decision
**Context**: [Circuit/algo where this matters]  
**Question**: [Cutoff freq? Gain? Delay time? Sample rate?]  
**Options**:
- $f_c = 15$ kHz: [pro/con]
- $f_c = 20$ kHz: [pro/con]
- $f_c = 25$ kHz: [pro/con]

**Decision**: $f_c = [X]$ kHz  
**Rationale**: [Spec requirement / bandwidth / Nyquist consideration]  
**Verified by**: [Sim / measurement / calculation]  

---

### Hardware/Budget Decision
**Context**: [What you needed]  
**Options**:
- [Component A] (~$X): [specs] — [pro/con]
- [Component B] (~$X): [specs] — [pro/con]

**Decision**: [Component X]  
**Rationale**: [Cost/performance/availability/ease]  
**Trade-off**: [Size/precision/complexity given up]  

---

## Reflection
**What went well**: [One thing you nailed]  
**What was friction**: [One thing that slowed you]  
**Next week priority**: [Unblock X so Y can proceed]  
**Excitement level**: [What part do you actually want to build next?]

---

## Weekly Checklist
- [ ] All sessions logged with date + time
- [ ] Metrics captured (sim results, scope data, synthesis stats)
- [ ] Blockers documented + resolved
- [ ] Decision rationale recorded
- [ ] Next week's first task identified


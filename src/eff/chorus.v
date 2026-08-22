/*==============================================================
 * CHORUS EFFECT MODULE
 *
 * A digital chorus effect for FPGA guitar pedal.
 *
 * Features:
 * - Triangle-wave LFO (32-bit phase accumulator, sample-rate locked)
 * - Circular delay line with LFO-modulated delay length
 * - Fractional-sample delay via 8-bit linear interpolation
 *   (no zipper noise as the delay sweeps)
 * - Linear dry/wet crossfade mix
 * - Makeup gain stage at the very end of the chain (per
 *   axi_template.v requirement)
 * - AXI-Stream handshake with direct backpressure coupling
 *
 * Architecture:
 * [Input] -> LFO (triangle) -> Modulated Delay (linear interp)
 *   -> Dry/Wet Crossfade -> Makeup Gain -> Output
 *
 *==============================================================
 * PARAMETER CONFIGURATION
 *==============================================================
 *
 * rate (16-bit unsigned)
 *   LFO phase increment per sample, left-shifted 8 into the
 *   32-bit accumulator: f_lfo = rate * fs / 2^24.
 *   Absolute range:    0x0000 (LFO frozen) to 0xFFFF (~187 Hz @ 48 kHz)
 *   Usable range:      0x0059 (~0.25 Hz) to 0x0DA7 (~10 Hz) @ 48 kHz
 *   Default:           0x015E (~1 Hz) / 0x03E8 (~2.9 Hz) @ 48 kHz
 *   Note: Scale linearly with sample rate (rate = f_hz * 2^24 / fs).
 *
 * depth (16-bit unsigned Q0.16)
 *   Modulation swing as a fraction of half the delay buffer:
 *   +/- (depth/65536) * (DELAY_DEPTH/2) samples.
 *   Absolute range:    0x0000 (static delay) to 0xFFFF (+/-1024 smp)
 *   Usable range:      0x0400 (+/-64 smp, 1.3 ms) to
 *                      0x8000 (+/-512 smp, 10.7 ms) @ 48 kHz
 *   Default:           0x2000 (+/-128 smp, ~2.7 ms)
 *   Note: Values > 0x8000 drive the delay into the end-of-buffer
 *         clamps (sweep flattens at extremes).
 *
 * mix (16-bit unsigned Q0.16)
 *   Linear dry/wet crossfade fraction.
 *   Absolute range:    0x0000 (dry only / bypass) to 0xFFFF (wet only)
 *   Usable range:      0x4000 (75/25) to 0xC000 (25/75)
 *   Default:           0x8000 (50/50)
 *   Note: 50/50 costs ~3 dB (decorrelated wet) up to ~6 dB
 *         (wor case); restore level with makeup_gain.
 *
 * makeup_gain (16-bit signed Q2.13 — matches sub_gain FRAC_BITS=13)
 *   Absolute range:    0x8000 (-4.0x) to 0x7FFF (+4.0x)
 *   Usable range:      0x2000 (0 dB) to 0x4000 (+6 dB)
 *   Unity:             0x2000 (1.0x)
 *   Default:           0x2D41 (+3 dB, restores 50/50 decorrelated mix)
 *   Note: Template header docs label this format Q1.14/unity 0x4000;
 *         sub_gain actually shifts by 13 (Q2.13, unity 0x2000).
 *         See TODO.
 *
 * DELAY_DEPTH (parameter, samples)
 *   Must be a power of 2, >= 16 (pointer wrap uses address
 *   truncation). Default 2048 = ~42.7 ms of buffer @ 48 kHz,
 *   base delay DELAY_DEPTH/2 = ~21.3 ms.
 *==============================================================
 * TODO
 * - Convert delay RAM to synchronous-read BRAM with a pipelined
 *   address/data path for timing closure at large depths
 * - Sine LFO option (smoother sweep than triangle)
 * - Stereo support (dual delay line, quadrature LFO)
 * - Auto-compute makeup gain from mix setting
 * - Reconcile Q1.14 vs Q2.13 documentation in template sub_gain
 *=============================================================*/

module chorus #(
    parameter WIDTH       = 24,
    parameter DELAY_DEPTH = 2048   // power of 2, >= 16
)(
    // === EFFECT-SPECIFIC CONTROL PARAMETERS ===
    input  wire [15:0] rate,         // LFO rate: f_lfo = rate*fs/2^24
    input  wire [15:0] depth,        // Q0.16 modulation depth
    input  wire [15:0] mix,          // Q0.16 dry/wet crossfade
    input  wire [15:0] makeup_gain,  // Q2.13 signed

    // === SYSTEM INTERFACE ===
    input  wire        tclk,
    input  wire        rst_n,

    // === AXI-STREAM INPUT ===
    input  wire [WIDTH-1:0] i_tdata,
    input  wire             i_tvalid,
    output wire             i_tready,

    // === AXI-STREAM OUTPUT ===
    input  wire             o_tready,
    output wire             o_tvalid,
    output reg  [WIDTH-1:0] o_tdata
);

    // Address width for the circular delay buffer
    localparam ADDR_W = $clog2(DELAY_DEPTH);

    //==========================================================
    // AXI-Stream handshake: direct combinational coupling
    //==========================================================
    assign i_tready = o_tready;
    assign o_tvalid = i_tvalid;

    //==========================================================
    // Internal state registers (ALL reset in always block below)
    //==========================================================
    reg  [31:0]       phase;                      // LFO phase accumulator
    reg  [ADDR_W-1:0] write_pos;                  // delay line write pointer
    reg  [WIDTH-1:0]  delay_ram [0:DELAY_DEPTH-1]; // circular sample buffer

    //==========================================================
    // Internal signal declarations
    //==========================================================
    wire [7:0]              lfo_tri;   // 0..255 unipolar triangle
    wire signed [23:0]      delay_q8;  // modulated delay, Q8 (8 frac bits)
    wire [ADDR_W-1:0]       int_delay; // integer part of delay
    wire [7:0]              frac;      // fractional part of delay
    wire [ADDR_W-1:0]       rd0, rd1;  // tap addresses
    wire signed [WIDTH-1:0] s0, s1;    // tap samples
    wire signed [WIDTH-1:0] wet;       // interpolated delay output
    wire signed [WIDTH-1:0] mixed;     // dry/wet crossfade output
    wire signed [WIDTH-1:0] makeup_applied;

    //==========================================================
    // Stage 1: LFO — triangle fold of the phase accumulator
    //==========================================================
    sub_lfo_tri u_lfo (
        .phase  (phase),
        .o_tri  (lfo_tri)
    );

    //==========================================================
    // Stage 2: Modulated delay length (Q8 samples, clamped)
    //==========================================================
    sub_mod_delay #(.DELAY_DEPTH(DELAY_DEPTH)) u_mod_delay (
        .depth_q016 (depth),
        .lfo_tri    (lfo_tri),
        .delay_q8   (delay_q8)
    );

    //==========================================================
    // Stage 3: Delay line taps — combinational RAM read
    //   rd0 = write_pos - delay. Min clamped delay of 2 samples
    //   guarantees rd0/rd1 never equal write_pos, so the
    //   combinational reads never collide with the write port.
    //==========================================================
    assign int_delay = delay_q8[ADDR_W+7:8]; // >>8, fits after clamp
    assign frac      = delay_q8[7:0];
    assign rd0       = write_pos - int_delay;
    assign rd1       = rd0 + 1'b1;           // circular wrap via truncation

    assign s0 = delay_ram[rd0];              // younger tap
    assign s1 = delay_ram[rd1];              // older tap

    //==========================================================
    // Stage 4: Fractional delay interpolation
    //   wet = s0 + ((s1 - s0) * frac) >> 8
    //==========================================================
    sub_lerp #(.WIDTH(WIDTH)) u_interp (
        .s0       (s0),
        .s1       (s1),
        .frac     (frac),
        .o_sample (wet)
    );

    //==========================================================
    // Stage 5: Dry/wet crossfade
    //   mixed = dry + ((wet - dry) * mix) >> 16
    //==========================================================
    sub_mix_xfade #(.WIDTH(WIDTH)) u_mix (
        .dry      (i_tdata),
        .wet      (wet),
        .mix_q016 (mix),
        .o_sample (mixed)
    );

    //==========================================================
    // Stage 6: Makeup gain — REQUIRED final stage (axi_template.v)
    //==========================================================
    sub_gain #(.WIDTH(WIDTH)) u_makeup (
        .i_sample  (mixed),
        .gain_q114 (makeup_gain),
        .o_sample  (makeup_applied)
    );

    //==========================================================
    // State + output register — gated by valid handshake
    // Reset of ALL internal state registers and o_tdata
    //==========================================================
    always @(posedge tclk or negedge rst_n) begin
        if (!rst_n) begin
            phase     <= 32'd0;
            write_pos <= {ADDR_W{1'b0}};
            o_tdata   <= {WIDTH{1'b0}};
            // delay_ram intentionally NOT reset here: inferred RAM has
            // no reset. Unwritten locations are don't-care until the
            // buffer first wraps; power-on init below covers sim.
        end else if (i_tvalid && o_tready) begin
            // LFO advance: increment = rate << 8 -> f = rate*fs/2^24
            phase <= phase + {rate, 8'b0};
            // Write current sample at write_pos, then advance pointer.
            // Safe: taps read >= 2 samples back, never this location.
            delay_ram[write_pos] <= i_tdata;
            write_pos <= write_pos + 1'b1;
            // Latch combinational DSP result
            o_tdata <= makeup_applied;
        end
    end

    // Power-on RAM init (synthesizable as FPGA memory init; keeps
    // simulation deterministic before the buffer first wraps)
    integer i;
    initial begin
        for (i = 0; i < DELAY_DEPTH; i = i + 1)
            delay_ram[i] = {WIDTH{1'b0}};
    end

endmodule


/*==============================================================
 * SUB-MODULE: sub_lfo_tri
 *
 * Unipolar triangle LFO folded from the top bits of the 32-bit
 * phase accumulator.
 *
 *   first half-cycle  (phase[31] = 0): ramp 0 -> 255
 *   second half-cycle (phase[31] = 1): ramp 255 -> 0
 *
 * phase : 32-bit phase accumulator (wraps once per LFO period)
 * o_tri : 0..255 triangle, one period per accumulator wrap
 *==============================================================*/
module sub_lfo_tri (
    input  wire [31:0] phase,
    output wire [7:0]  o_tri
);
    assign o_tri = phase[31] ? ~phase[30:23]   // fold falling ramp
                             :  phase[30:23];  // rising ramp
endmodule


/*==============================================================
 * SUB-MODULE: sub_mod_delay
 *
 * Computes the LFO-modulated delay length in Q8 fixed-point
 * samples (8 fractional bits):
 *
 *   delay = BASE + (depth/2^16) * lfo * (DELAY_DEPTH/2)
 *   lfo   = (tri - 128)/128,  -1.0 .. +0.99
 *
 * Result is clamped to [2, DELAY_DEPTH-2] samples so the
 * interpolator always has two valid taps and the read pointer
 * never collides with the write pointer.
 *
 * depth_q016 : Q0.16 modulation depth (0..65535)
 * lfo_tri    : 0..255 unipolar triangle from sub_lfo_tri
 * delay_q8   : modulated delay, Q8 samples, clamped
 *==============================================================*/
module sub_mod_delay #(
    parameter DELAY_DEPTH = 2048
)(
    input  wire [15:0]        depth_q016,
    input  wire [7:0]         lfo_tri,
    output wire signed [23:0] delay_q8
);
    // Delay limits in Q8 samples
    localparam signed [24:0] BASE_Q8 = (DELAY_DEPTH / 2) * 256;
    localparam signed [24:0] MIN_Q8  = 2 * 256;
    localparam signed [24:0] MAX_Q8  = (DELAY_DEPTH - 2) * 256;

    // Bipolar LFO: -128..+127 (~Q1.7, +/-1.0)
    wire signed [8:0] lfo_s = $signed({1'b0, lfo_tri}) - 9'sd128;

    // mod_prod = depth * lfo. Scaled to Q8 samples:
    //   (depth/2^16)*(lfo/2^7)*(DEPTH/2)*2^8 = depth*lfo*DEPTH/2^16
    // For DEPTH = 2^k this is a right shift by (16 - k).
    wire signed [24:0] mod_prod  = $signed({1'b0, depth_q016}) * lfo_s;
    wire signed [24:0] mod_q8    = mod_prod >>> (16 - $clog2(DELAY_DEPTH));
    wire signed [24:0] delay_raw = BASE_Q8 + mod_q8;

    assign delay_q8 = (delay_raw < MIN_Q8) ? MIN_Q8 :
                      (delay_raw > MAX_Q8) ? MAX_Q8 :
                                             delay_raw[23:0];
endmodule


/*==============================================================
 * SUB-MODULE: sub_lerp
 *
 * 8-bit linear interpolation between two delay taps, used for
 * fractional-sample delay (prevents zipper noise while the LFO
 * sweeps the delay length).
 *
 *   y = s0 + ((s1 - s0) * frac) >> 8,   frac = 0..255
 *
 * frac = 0   -> y = s0   (younger tap)
 * frac = 255 -> y ~ s1   (older tap)
 * Output saturated to WIDTH bits.
 *==============================================================*/
module sub_lerp #(
    parameter WIDTH = 24
)(
    input  wire signed [WIDTH-1:0] s0,
    input  wire signed [WIDTH-1:0] s1,
    input  wire        [7:0]       frac,
    output wire signed [WIDTH-1:0] o_sample
);
    localparam signed [WIDTH-1:0] MAX_VAL = {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] MIN_VAL = {1'b1, {(WIDTH-1){1'b0}}};

    wire signed [WIDTH:0]   diff   = s1 - s0;
    wire signed [WIDTH+8:0] prod   = diff * $signed({1'b0, frac});
    wire signed [WIDTH:0]   interp = s0 + (prod >>> 8);

    assign o_sample = (interp > MAX_VAL) ? MAX_VAL :
                      (interp < MIN_VAL) ? MIN_VAL :
                                           interp[WIDTH-1:0];
endmodule


/*==============================================================
 * SUB-MODULE: sub_mix_xfade
 *
 * Linear dry/wet crossfade:
 *
 *   y = dry + ((wet - dry) * mix) >> 16
 *
 * mix_q016 = 0x0000 -> dry only (bypass)
 * mix_q016 = 0x8000 -> 50/50 blend
 * mix_q016 = 0xFFFF -> wet only
 *
 * The result is a convex combination of dry and wet, so it can
 * never exceed the input magnitude range; the clamp is defensive.
 *==============================================================*/
module sub_mix_xfade #(
    parameter WIDTH = 24
)(
    input  wire signed [WIDTH-1:0] dry,
    input  wire signed [WIDTH-1:0] wet,
    input  wire        [15:0]      mix_q016,
    output wire signed [WIDTH-1:0] o_sample
);
    localparam signed [WIDTH-1:0] MAX_VAL = {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] MIN_VAL = {1'b1, {(WIDTH-1){1'b0}}};

    wire signed [WIDTH:0]    diff  = wet - dry;
    wire signed [WIDTH+16:0] prod  = diff * $signed({1'b0, mix_q016});
    wire signed [WIDTH:0]    mixed = dry + (prod >>> 16);

    assign o_sample = (mixed > MAX_VAL) ? MAX_VAL :
                      (mixed < MIN_VAL) ? MIN_VAL :
                                          mixed[WIDTH-1:0];
endmodule


/*==============================================================
 * SUB-MODULE: sub_gain
 *
 * Signed Q1.14 fixed-point multiplication with saturation.
 * Same as sim/hard_clip/hard_clip.v:sub_gain.
 *
 * i_sample   : signed WIDTH-bit audio sample
 * gain_q114  : signed Q1.14 coefficient (unity = 0x4000)
 * o_sample   : saturated WIDTH-bit result
 *==============================================================*/
module sub_gain #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] i_sample,
    input  signed [15:0]      gain_q114,
    output signed [WIDTH-1:0] o_sample
);
    localparam FRAC_BITS = 13;

    wire signed [(WIDTH + 16) - 1:0] temp;
    assign temp = i_sample * gain_q114;

    wire signed [(WIDTH + 16) - 1:0] rounded = temp + (1 << (FRAC_BITS - 1));
    wire signed [(WIDTH + 16) - 1:0] shifted = rounded >>> FRAC_BITS;

    // Saturation bounds for signed WIDTH-bit
    localparam signed [WIDTH-1:0] MAX_VAL = {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] MIN_VAL = {1'b1, {(WIDTH-1){1'b0}}};

    wire overflow  = (shifted > MAX_VAL);
    wire underflow = (shifted < MIN_VAL);

    assign o_sample = overflow  ? MAX_VAL :
                      underflow ? MIN_VAL :
                                  shifted[WIDTH-1:0];
endmodule

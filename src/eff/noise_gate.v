/*==============================================================
 * NOISE GATE EFFECT MODULE
 *
 * A noise gate that mutes the signal when its level falls below
 * a threshold, silencing noise during quiet passages.
 *
 * Features:
 * - Peak-follower envelope detection with fast-attack/slow-release
 * - Comparator with adjustable threshold
 * - Smooth attack/release ramping to avoid clicks and pops
 * - Makeup gain stage for output level compensation
 * - AXI-Stream handshake with direct backpressure coupling
 *
 * Architecture:
 * Input -> Envelope Detector -> Comparator -> Smooth Gain
 *   -> Makeup Gain -> Output
 *
 *==============================================================
 * PARAMETER CONFIGURATION
 *==============================================================
 *
 * threshold (16-bit Q0.16 unsigned)
 *   Absolute range:    0x0000 (gate always open) to 0xFFFF (gate always closed)
 *   Usable range:      0x0000-0x8000
 *   Default:           0x1000 (~6% of full scale)
 *   Note: Level below which the gate closes. Higher = more aggressive gating.
 *
 * attack (16-bit unsigned)
 *   Absolute range:    0 (instant) to 65535
 *   Usable range:      0-10000 (~0-200ms @ 48kHz)
 *   Default:           500 (~10ms @ 48kHz)
 *   Note: How fast the gate opens (in samples). 0 = instant.
 *
 * release_len (16-bit unsigned)
 *   Absolute range:    0 (instant) to 65535
 *   Usable range:      0-50000 (~0-1s @ 48kHz)
 *   Default:           5000 (~100ms @ 48kHz)
 *   Note: How fast the gate closes (in samples). 0 = instant.
 *
 * makeup_gain (16-bit Q2.13 signed)
 *   Absolute range:    0x8000 (-4.0x) to 0x7FFF (+3.9999x)
 *   Unity gain:        16'd4096 (0x1000, 1.0x)
 *   Note: Post-gate makeup gain to compensate for signal reduction.
 *==============================================================
 * TODO
 * - None
 *=============================================================*/

module noise_gate #(
    parameter WIDTH = 24
)(
    // === EFFECT-SPECIFIC CONTROL PARAMETERS ===
    input  wire [15:0] threshold,    // Q0.16 unsigned
    input  wire [15:0] attack,       // attack length in samples
    input  wire [15:0] release_len,  // release length in samples
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

    //==========================================================
    // AXI-Stream handshake: direct combinational coupling
    //==========================================================
    assign i_tready = o_tready;
    assign o_tvalid = i_tvalid;

    //==========================================================
    // Internal signal declarations
    //==========================================================

    // -- Envelope detector --
    reg  signed [WIDTH-1:0] envelope;
    wire signed [WIDTH-1:0] abs_sample;
    wire signed [WIDTH-1:0] leakage;

    // -- Comparator --
    wire signed [WIDTH-1:0] scaled_threshold;
    wire                    gate_open;

    // -- Smooth gain ramping --
    reg  [15:0]             ramp_counter;  // counts 0..attack or 0..release_len
    reg                     gate_is_open;  // registered gate state (1 = open, 0 = closed)
    wire signed [15:0]      gain_q114;     // Q1.14 gain coefficient

    // -- Pipeline signals --
    wire signed [WIDTH-1:0] gated;
    wire signed [WIDTH-1:0] makeup_applied;

    //==========================================================
    // Stage 1: Envelope detection (peak follower)
    //
    // Fast-attack: envelope jumps to abs_sample immediately when
    //   the new sample exceeds the current envelope.
    // Slow-release: envelope decays by subtracting a leakage term
    //   when the sample is below the envelope.
    //==========================================================
    assign abs_sample = i_tdata[WIDTH-1] ? -i_tdata : i_tdata;
    assign leakage    = envelope >>> 12;  // ~10ms decay constant @ 48kHz

    //==========================================================
    // Stage 2: Comparator
    //
    // Scale the 16-bit Q0.16 threshold into the WIDTH-bit signed
    // sample domain, then compare against the envelope.
    //==========================================================
    assign scaled_threshold = $signed({1'b0, threshold}) <<< (WIDTH - 16);
    assign gate_open        = (envelope > scaled_threshold);

    //==========================================================
    // Stage 3: Smooth gain with attack/release ramping
    //
    //   gate opens: ramp_counter counts 0 -> attack
    //     gain = ramp_counter / attack  (linear ramp 0.0 -> 1.0)
    //
    //   gate closes: ramp_counter counts 0 -> release_len
    //     gain = 1.0 - (ramp_counter / release_len) (linear ramp 1.0 -> 0.0)
    //
    //   attack = 0  -> instant open (gain jumps to 1.0)
    //   release_len = 0 -> instant close (gain jumps to 0.0)
    //
    // gain_q114 is Q1.14 format: 0x0000 = 0.0, 0x4000 = 1.0
    //==========================================================

    // Combinational gain calculation based on registered gate state
    // and current ramp counter position.
    assign gain_q114 = gate_is_open
        ? ((attack == 16'd0) ? 16'h4000 : $signed({1'b0, ramp_counter}) * 16'h4000 / $signed({1'b0, attack}))
        : ((release_len == 16'd0) ? 16'h0000 : (16'h4000 - ($signed({1'b0, ramp_counter}) * 16'h4000 / $signed({1'b0, release_len}))));

    // Apply smoothed gain to the input signal
    sub_gain #(.WIDTH(WIDTH)) gate_gain_stage (
        .i_sample  (i_tdata),
        .gain_q114 (gain_q114),
        .o_sample  (gated)
    );

    //==========================================================
    // Stage 4: Makeup gain (signed Q2.13 -> Q1.14 compatible)
    //
    // Compensate for overall level reduction after gating.
    //==========================================================
    sub_gain #(.WIDTH(WIDTH)) makeup_gain_stage (
        .i_sample  (gated),
        .gain_q114 (makeup_gain),
        .o_sample  (makeup_applied)
    );

    //==========================================================
    // State update — gated by valid handshake
    //
    // Updates envelope, ramp counter, gate state, and output
    // register only when i_tvalid && o_tready.
    //==========================================================
    always @(posedge tclk or negedge rst_n) begin
        if (!rst_n) begin
            o_tdata      <= {WIDTH{1'b0}};
            envelope     <= {WIDTH{1'b0}};
            ramp_counter <= 16'd0;
            gate_is_open <= 1'b0;
        end else if (i_tvalid && o_tready) begin
            o_tdata <= makeup_applied;

            // --- Envelope follower ---
            if (abs_sample > envelope) begin
                envelope <= abs_sample;       // fast attack
            end else begin
                envelope <= envelope - leakage; // slow release
            end

            // --- Ramp counter and gate_is_open ---
            if (gate_open) begin
                gate_is_open <= 1'b1;
                if (attack == 16'd0) begin
                    ramp_counter <= 16'd0;    // instant open
                end else if (ramp_counter < attack) begin
                    ramp_counter <= ramp_counter + 16'd1;
                end
                // else: counter saturated at attack — hold
            end else begin
                gate_is_open <= 1'b0;
                if (release_len == 16'd0) begin
                    ramp_counter <= 16'd0;    // instant close
                end else if (ramp_counter < release_len) begin
                    ramp_counter <= ramp_counter + 16'd1;
                end
                // else: counter saturated at release_len — hold
            end
        end
    end

endmodule


/*==============================================================
 * SUB-MODULE: sub_gain
 *
 * Signed Q1.14 fixed-point multiplication with saturation.
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

    localparam signed [WIDTH-1:0] MAX_VAL = {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] MIN_VAL = {1'b1, {(WIDTH-1){1'b0}}};

    wire overflow  = (shifted > MAX_VAL);
    wire underflow = (shifted < MIN_VAL);

    assign o_sample = overflow  ? MAX_VAL :
                      underflow ? MIN_VAL :
                                  shifted[WIDTH-1:0];
endmodule

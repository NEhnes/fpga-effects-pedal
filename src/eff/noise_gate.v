/*==============================================================
 * NOISE GATE EFFECT MODULE (SIMPLIFIED)
 *  
 * MAY NEED TO BE PIPELINED
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
 *   Note: How fast the gate opens (in samples). 0 = instant. fade-in type effect
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
 *==============================================================*/

module noise_gate #(
    parameter WIDTH = 24
)(
    // === EFFECT-SPECIFIC CONTROL PARAMETERS ===
    input  wire [15:0] threshold,    // Q0.16 unsigned
    input  wire [15:0] attack,       // attack length in samples
    input  wire [15:0] release_len,  // release length in samples
    input  signed [15:0] makeup_gain,  // Q2.13 signed

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
    reg  [15:0]             ramp_counter;  // counts during attack/release
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
    // Ramp counter increments when transitioning between states.
    // On attack (gate_is_open = 0 but gate_open = 1):
    //   gain = ramp_counter / attack
    // On release (gate_is_open = 1 but gate_open = 0):
    //   gain = (release_len - ramp_counter) / release_len
    //
    // Special cases (attack or release = 0) handled by clamping gain.
    //
    // gain_q114 is Q1.14 format: 0x0000 = 0.0, 0x4000 = 1.0
    //==========================================================

    // Determine ramp direction: use gate_open to see where we're going
    // If gate_open, we're opening (attack ramp); if not, we're closing (release ramp)
    wire ramp_is_attack = gate_open;
    wire ramp_done_attack = (ramp_counter >= attack) || (attack == 16'd0);
    wire ramp_done_release = (ramp_counter >= release_len) || (release_len == 16'd0);

    // Compute gain based on current ramp position
    wire signed [31:0] ramp_num;
    wire signed [31:0] ramp_denom;
    wire signed [31:0] ramp_frac;

    // Attack: gain = counter / attack (0.0 -> 1.0)
    // Release: gain = (len - counter) / len (1.0 -> 0.0)
    // Use gate_open (combinational) to respond immediately to threshold crossing
    assign ramp_num = ramp_is_attack
        ? $signed({1'b0, ramp_counter})
        : $signed({1'b0, release_len}) - $signed({1'b0, ramp_counter});

    assign ramp_denom = ramp_is_attack ? $signed({1'b0, attack}) : $signed({1'b0, release_len});

    // Avoid division by zero
    assign ramp_frac = (ramp_denom == 32'd0)
        ? (ramp_is_attack ? 32'h4000 : 32'h0000)
        : (ramp_num * 32'h4000) / ramp_denom;

    assign gain_q114 = ramp_frac[15:0];

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

            // --- Gate state and ramp counter ---
            // Compare combinational gate_open with registered gate_is_open
            if (gate_open != gate_is_open) begin
                // Direction change: just update gate_is_open
                // Counter will start fresh but continues on next cycle
                gate_is_open <= gate_open;
            end
            
            // Always increment counter when ramping (don't stop on direction change)
            if ((gate_open && !ramp_done_attack) || (!gate_open && !ramp_done_release)) begin
                ramp_counter <= ramp_counter + 16'd1;
            end else begin
                // Ramp complete or not ramping: reset counter for next ramp
                ramp_counter <= 16'd0;
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

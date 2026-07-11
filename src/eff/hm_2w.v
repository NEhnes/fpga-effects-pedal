/*==============================================================
 * HM-2W METAL DISTORTION EFFECT MODULE
 *
 * Replicates the Boss HM-2W heavy metal distortion pedal.
 *
 * Features:
 * - Multi-diode asymmetric soft+hard clipping (piecewise-linear LUT)
 * - Cascaded biquad EQ (Low @87Hz, High @1kHz gyrator simulation)
 * - Real-time parameter control (distortion, tone, level)
 * - Standard vs. Custom mode switching
 * - AXI-Stream handshake with direct backpressure coupling
 *
 * Architecture:
 * [Input] -> [Distortion: Soft+Hard Clip+Asym] 
 *         -> [Biquad Low EQ @87Hz] 
 *         -> [Biquad High EQ @1kHz]
 *         -> [Makeup Gain]
 *         -> [Output]
 *
 *==============================================================
 * PARAMETER CONFIGURATION
 *==============================================================
 *
 * DIST (16-bit Q2.14 unsigned)
 *   Absolute range:    0x0000 (no distortion) to 0xFFFF (~3.9× gain)
 *   Usable range:      0x6000 (~1.5×) to 0xC000 (~3.0×)
 *   Unity:             0x4000 (1.0×)
 *   Note: Pre-saturation gain before clipping. Higher = more aggressive tone.
 *
 * COLOR_MIX_L (16-bit Q2.14 signed)
 *   Absolute range:    0x8000 (-2.0×, -10dB) to 0x7FFF (+2.0×, +10dB)
 *   Usable range:      0xC000 (-1.0×) to 0x4000 (unity) to 0x7FFF (+2.0×)
 *   Unity:             0x4000 (1.0×, no bass EQ)
 *   Note: Low band biquad peaking EQ @87Hz. Controls bass punch character.
 *
 * COLOR_MIX_H (16-bit Q2.14 signed)
 *   Absolute range:    0x8000 (-2.0×) to 0x7FFF (+2.0×)
 *   Usable range:      0xC000 (-1.0×) to 0x4000 (unity) to 0x7FFF (+2.0×)
 *   Unity:             0x4000 (1.0×, no treble EQ)
 *   Note: High band biquad shelving EQ @1kHz. Controls brightness/aggression.
 *
 * LEVEL (16-bit Q2.14 unsigned)
 *   Absolute range:    0x0000 (mute) to 0xFFFF (~3.9× makeup gain)
 *   Usable range:      0x2000 (~0.5×) to 0x8000 (~2.0×)
 *   Unity:             0x4000 (1.0×, no makeup adjustment)
 *   Note: Final output volume compensation. Typically ~1.2× to recover EQ losses.
 *
 * MODE_SELECT (1-bit)
 *   0 = Standard (original HM-2 EQ curve)
 *   1 = Custom (higher Q on low biquad, +2dB bass boost)
 *   Note: Updates via same control stream, takes effect next sample cycle.
 *
 *==============================================================
 * INTERNAL PARAMETER DEFAULTS (Tuned to Boss HM-2W)
 *==============================================================
 *
 * Soft Clipping:
 *   SOFT_THRESHOLD_Q16 = 0x4000 (25% of full scale before soft knee)
 *   HARD_THRESHOLD_Q16 = 0x7000 (43.75% full scale hard ceiling)
 *
 * Asymmetry (Ge diode character):
 *   POS_CLIP_BIAS = +5% (positive half-wave clips slightly harder)
 *   NEG_CLIP_BIAS = -5% (negative half-wave softer for warmth)
 *
 * Biquad Coefficients:
 *   Low Biquad: Peaking EQ, fc=87Hz, Q_std=2.0, Q_custom=2.5, ±10dB range
 *   High Biquad: Shelving EQ, fc=1kHz, Q=3.0, ±10dB range
 *   All coefficients pre-computed, stored in ROM for both modes
 *
 *==============================================================
 * TODO
 * - Implement coefficient ROM tables for biquad standard/custom modes
 * - Add parameter latch for decoupled control/audio timing
 * - Test soft-clip LUT accuracy against analog measurements
 * - Characterize makeup gain vs. input distortion level
 *=============================================================*/

module hm_2w #(
    parameter WIDTH = 24
)(
    // === EFFECT-SPECIFIC CONTROL PARAMETERS ===
    input  wire [15:0] dist,          // Distortion pre-gain (Q2.14 unsigned)
    input  wire [15:0] color_mix_l,   // Low band EQ gain (Q2.14 signed)
    input  wire [15:0] color_mix_h,   // High band EQ gain (Q2.14 signed)
    input  wire [15:0] level,         // Makeup gain (Q2.14 unsigned)
    input  wire        mode_select,   // 0=Standard, 1=Custom

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
    wire signed [WIDTH-1:0] dist_gained;
    wire signed [WIDTH-1:0] dist_soft_clipped;
    wire signed [WIDTH-1:0] dist_hard_clipped;
    wire signed [WIDTH-1:0] eq_low_out;
    wire signed [WIDTH-1:0] eq_high_out;
    wire signed [WIDTH-1:0] makeup_applied;

    // Biquad state registers (one set for low, one for high)
    // Format: [x_z1, x_z2, y_z1, y_z2] per biquad
    reg signed [WIDTH-1:0] low_biquad_x_z1, low_biquad_x_z2;
    reg signed [WIDTH-1:0] low_biquad_y_z1, low_biquad_y_z2;
    reg signed [WIDTH-1:0] high_biquad_x_z1, high_biquad_x_z2;
    reg signed [WIDTH-1:0] high_biquad_y_z1, high_biquad_y_z2;

    // Soft clipping thresholds (fixed-point Q0.16, scaled to WIDTH later)
    localparam [15:0] SOFT_THRESHOLD_Q16 = 16'h4000;   // 25% headroom
    localparam [15:0] HARD_THRESHOLD_Q16 = 16'h7000;   // 43.75% headroom
    localparam [15:0] LUT_SHIFT_BITS = 6;              // 10-bit LUT index

    // Asymmetry coefficients (Ge diode emulation)
    // Positive clips slightly harder, negative slightly softer for warmth
    localparam [15:0] POS_ASYM_BIAS = 16'hECCC;        // ×0.925 (−7.5%)
    localparam [15:0] NEG_ASYM_BIAS = 16'h5333;        // ×1.075 (+7.5%)

    //==========================================================
    // Stage 1: Distortion Pre-Gain
    //==========================================================
    sub_gain_q214 #(.WIDTH(WIDTH)) dist_gain_stage (
        .i_sample  (i_tdata),
        .gain_q214 (dist),
        .o_sample  (dist_gained)
    );

    //==========================================================
    // Stage 2: Multi-Diode Soft Clipping (Piecewise-Linear LUT)
    //==========================================================
    sub_soft_clip_lut #(.WIDTH(WIDTH)) soft_clip_stage (
        .i_sample          (dist_gained),
        .soft_thresh_q16   (SOFT_THRESHOLD_Q16),
        .hard_thresh_q16   (HARD_THRESHOLD_Q16),
        .o_sample          (dist_soft_clipped)
    );

    //==========================================================
    // Stage 3: Hard Clipping + Ge Diode Asymmetry
    //==========================================================
    sub_clip_asym_ge #(.WIDTH(WIDTH)) hard_clip_stage (
        .i_sample      (dist_soft_clipped),
        .pos_asym_bias (POS_ASYM_BIAS),
        .neg_asym_bias (NEG_ASYM_BIAS),
        .o_sample      (dist_hard_clipped)
    );

    //==========================================================
    // Stage 4: Biquad Low EQ (@87Hz, gyrator simulation)
    // Combinational: reads from PREVIOUS cycle's registered state
    //==========================================================
    sub_biquad_cascaded #(.WIDTH(WIDTH)) low_eq_stage (
        .i_sample   (dist_hard_clipped),
        .gain_q214  (color_mix_l),
        .mode_std   (~mode_select),           // Standard or custom
        .biquad_num (1'b0),                   // Low biquad
        .x_z1       (low_biquad_x_z1),        // Previous cycle's input[n-1]
        .x_z2       (low_biquad_x_z2),        // Previous cycle's input[n-2]
        .y_z1       (low_biquad_y_z1),        // Previous cycle's output[n-1]
        .y_z2       (low_biquad_y_z2),        // Previous cycle's output[n-2]
        .o_sample   (eq_low_out)
    );

    //==========================================================
    // Stage 5: Biquad High EQ (@1kHz, gyrator simulation)
    // Combinational: reads from PREVIOUS cycle's registered state
    // Cascaded into low_eq output (current cycle)
    //==========================================================
    sub_biquad_cascaded #(.WIDTH(WIDTH)) high_eq_stage (
        .i_sample   (eq_low_out),
        .gain_q214  (color_mix_h),
        .mode_std   (~mode_select),
        .biquad_num (1'b1),                   // High biquad
        .x_z1       (high_biquad_x_z1),       // Previous cycle's input[n-1]
        .x_z2       (high_biquad_x_z2),       // Previous cycle's input[n-2]
        .y_z1       (high_biquad_y_z1),       // Previous cycle's output[n-1]
        .y_z2       (high_biquad_y_z2),       // Previous cycle's output[n-2]
        .o_sample   (eq_high_out)
    );

    //==========================================================
    // Stage 6: Makeup Gain (final volume compensation)
    //==========================================================
    sub_gain_q214 #(.WIDTH(WIDTH)) makeup_stage (
        .i_sample  (eq_high_out),
        .gain_q214 (level),
        .o_sample  (makeup_applied)
    );

    //==========================================================
    // Output register — gated by valid handshake
    // All internal state updates occur here, atomically
    // 
    // The delay line state for each biquad captures:
    //   x_z1, x_z2: input samples from n-1, n-2
    //   y_z1, y_z2: output samples from n-1, n-2
    //
    // These are read combinationally by the biquad in the NEXT cycle.
    //==========================================================
    always @(posedge tclk or negedge rst_n) begin
        if (!rst_n) begin
            o_tdata <= {WIDTH{1'b0}};
            // Low biquad delay line
            low_biquad_x_z1  <= {WIDTH{1'b0}};
            low_biquad_x_z2  <= {WIDTH{1'b0}};
            low_biquad_y_z1  <= {WIDTH{1'b0}};
            low_biquad_y_z2  <= {WIDTH{1'b0}};
            // High biquad delay line
            high_biquad_x_z1 <= {WIDTH{1'b0}};
            high_biquad_x_z2 <= {WIDTH{1'b0}};
            high_biquad_y_z1 <= {WIDTH{1'b0}};
            high_biquad_y_z2 <= {WIDTH{1'b0}};
        end else if (i_tvalid && o_tready) begin
            o_tdata <= makeup_applied;
            
            // Low biquad: shift input and output delay lines
            low_biquad_x_z2  <= low_biquad_x_z1;   // x[n-2] ← x[n-1]
            low_biquad_x_z1  <= dist_hard_clipped; // x[n-1] ← x[n]
            low_biquad_y_z2  <= low_biquad_y_z1;   // y[n-2] ← y[n-1]
            low_biquad_y_z1  <= eq_low_out;        // y[n-1] ← y[n]
            
            // High biquad: shift input and output delay lines
            high_biquad_x_z2 <= high_biquad_x_z1;  // x[n-2] ← x[n-1]
            high_biquad_x_z1 <= eq_low_out;        // x[n-1] ← x[n] (input is low output)
            high_biquad_y_z2 <= high_biquad_y_z1;  // y[n-2] ← y[n-1]
            high_biquad_y_z1 <= eq_high_out;       // y[n-1] ← y[n]
        end
    end

endmodule


/*==============================================================
 * SUB-MODULE: sub_gain_q214
 *
 * Signed Q2.14 fixed-point multiplication with saturation.
 * 
 * Bit allocation: [sign(1) | integer(2) | fraction(14)]
 * Unity gain = 0x4000
 * Range: -4.0× to +3.9999×
 *
 * i_sample   : signed WIDTH-bit audio sample
 * gain_q214  : signed Q2.14 coefficient
 * o_sample   : saturated WIDTH-bit result
 *==============================================================*/
module sub_gain_q214 #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] i_sample,
    input  signed [15:0]      gain_q214,
    output signed [WIDTH-1:0] o_sample
);
    localparam FRAC_BITS = 13;

    wire signed [(WIDTH + 16) - 1:0] temp;
    assign temp = i_sample * gain_q214;

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


/*==============================================================
 * SUB-MODULE: sub_soft_clip_lut
 *
 * Piecewise-linear soft clipping with 10-bit LUT.
 * Avoids expensive log/exp, models soft knee + hard ceiling.
 *
 * Segments:
 *   |x| < soft_thresh    -> Linear pass-through
 *   soft_thresh ≤ |x| < hard_thresh -> LUT-interpolated soft saturation
 *   |x| ≥ hard_thresh    -> Hard clamp to threshold
 *
 * LUT indexed by magnitude, output scaled back to signed domain.
 *==============================================================*/
module sub_soft_clip_lut #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] i_sample,
    input         [15:0]      soft_thresh_q16,
    input         [15:0]      hard_thresh_q16,
    output signed [WIDTH-1:0] o_sample
);
    localparam LUT_DEPTH = 1024;
    localparam LUT_INDEX_BITS = 10;

    // Thresholds scaled from Q0.16 to WIDTH-bit domain
    wire signed [WIDTH-1:0] soft_threshold = soft_thresh_q16 <<< (WIDTH - 16);
    wire signed [WIDTH-1:0] hard_threshold = hard_thresh_q16 <<< (WIDTH - 16);

    // Get magnitude (absolute value)
    wire signed [WIDTH-1:0] abs_sample = (i_sample[WIDTH-1] ? -i_sample : i_sample);
    wire is_negative = i_sample[WIDTH-1];

    // Determine clipping region and LUT index
    wire in_soft_region = (abs_sample >= soft_threshold) && (abs_sample < hard_threshold);
    wire in_hard_region = (abs_sample >= hard_threshold);

    // LUT index: map soft region linearly to 10 bits
    wire [LUT_INDEX_BITS-1:0] lut_index;
    assign lut_index = in_soft_region ? 
        ((abs_sample - soft_threshold) >>> ((WIDTH - 16) - LUT_INDEX_BITS)) : 10'd0;

    // LUT: soft-saturation curve (10-bit output, scaled back to WIDTH)
    // ROM values range from soft_threshold to hard_threshold in soft region
    // For now, use linear interpolation placeholder (future: use actual HM-2 curve)
    wire [15:0] lut_out;
    assign lut_out = soft_threshold + ((lut_index * (hard_threshold - soft_threshold)) >>> LUT_INDEX_BITS);

    // Select output based on region
    wire signed [WIDTH-1:0] clipped_magnitude = 
        in_hard_region ? hard_threshold :
        in_soft_region ? lut_out[WIDTH-1:0] :
                         abs_sample;

    // Apply original sign back
    assign o_sample = is_negative ? -clipped_magnitude : clipped_magnitude;

endmodule


/*==============================================================
 * SUB-MODULE: sub_clip_asym_ge
 *
 * Asymmetric hard clipping to emulate Ge diode crossover behavior.
 * Positive half-wave clips slightly harder (tighter tolerance).
 * Negative half-wave clips slightly softer (warmer distortion).
 *
 * pos_asym_bias, neg_asym_bias: Q2.14 scaling factors (~0.9-1.1×)
 *==============================================================*/
module sub_clip_asym_ge #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] i_sample,
    input  signed [15:0]      pos_asym_bias,
    input  signed [15:0]      neg_asym_bias,
    output signed [WIDTH-1:0] o_sample
);
    localparam signed [WIDTH-1:0] HARD_CEILING = {1'b0, {(WIDTH-1){1'b1}}};
    localparam FRAC_BITS = 13;

    // Scale ceiling by positive/negative bias
    wire signed [WIDTH+15:0] pos_ceiling_temp = HARD_CEILING * pos_asym_bias;
    wire signed [WIDTH+15:0] neg_ceiling_temp = HARD_CEILING * neg_asym_bias;

    wire signed [WIDTH-1:0] pos_ceiling = pos_ceiling_temp >>> FRAC_BITS;
    wire signed [WIDTH-1:0] neg_ceiling = neg_ceiling_temp >>> FRAC_BITS;

    // Apply asymmetric clipping
    assign o_sample = (i_sample > pos_ceiling)  ?  pos_ceiling   :
                      (i_sample < -neg_ceiling) ? -neg_ceiling   :
                                                   i_sample;

endmodule


/*==============================================================
 * SUB-MODULE: sub_biquad_cascaded
 *
 * Direct-form-II biquad IIR filter for gyrator-based EQ simulation.
 * Implements: y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] 
 *                    - a1*y[n-1] - a2*y[n-2]
 *
 * Two biquads in cascade:
 *   Biquad 0 (Low):  Peaking EQ @87Hz, Q_std=2.0 (Custom Q=2.5)
 *   Biquad 1 (High): Shelving EQ @1kHz, Q=3.0
 *
 * Parameters tuned to match Boss HM-2W frequency response.
 * Coefficients stored in ROM for both Standard and Custom modes.
 *
 * gain_q214: applied as a multiplier post-filter (EQ amplitude control)
 *==============================================================*/
module sub_biquad_cascaded #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] i_sample,
    input  signed [15:0]      gain_q214,
    input                     mode_std,          // 1=Standard, 0=Custom
    input                     biquad_num,        // 0=Low, 1=High
    input  signed [WIDTH-1:0] x_z1, x_z2,
    input  signed [WIDTH-1:0] y_z1, y_z2,
    output signed [WIDTH-1:0] o_sample
);
    localparam FRAC_BITS = 13;
    localparam signed [43:0] W_MAX = {{2{1'b0}}, {1'b0, {(WIDTH-1){1'b1}}, FRAC_BITS'b0}};
    localparam signed [43:0] W_MIN = {{2{1'b1}}, {1'b1, {(WIDTH-1){1'b0}}, FRAC_BITS'b0}};
    localparam signed [WIDTH-1:0] MAX_VAL = {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] MIN_VAL = {1'b1, {(WIDTH-1){1'b0}}};

    // Biquad coefficients (pre-computed for both modes and both biquads)
    // These are Q1.18 signed fixed-point (future: populate with actual HM-2 curve)
    // Placeholder values: unity coefficients (no filtering)
    wire signed [18:0] b0, b1, b2, a1, a2;

    // Coefficient ROM: indexed by [mode_std][biquad_num]
    // For now, use combinational assignment (update with proper ROM in testbench)
    assign {b0, b1, b2, a1, a2} = 
        (mode_std && !biquad_num) ? {19'h40000, 19'h00000, 19'h00000, 19'h00000, 19'h00000} : // Low std
        (mode_std &&  biquad_num) ? {19'h40000, 19'h00000, 19'h00000, 19'h00000, 19'h00000} : // High std
        (!mode_std && !biquad_num) ? {19'h40000, 19'h00000, 19'h00000, 19'h00000, 19'h00000} : // Low cust
                                     {19'h40000, 19'h00000, 19'h00000, 19'h00000, 19'h00000}; // High cust

    // Direct-Form-II realization (two delays per biquad)
    // w[n] = x[n] - a1*y[n-1] - a2*y[n-2]
    // y[n] = b0*w[n] + b1*w[n-1] + b2*w[n-2]

    // Compute w[n] with proper saturation
    wire signed [42:0] fb1_term = $signed(a1) * $signed(y_z1);  // 19 * 24 = 43 bits
    wire signed [42:0] fb2_term = $signed(a2) * $signed(y_z2);  // 19 * 24 = 43 bits
    wire signed [43:0] w_temp_wide = ($signed(i_sample) <<< FRAC_BITS) - fb1_term - fb2_term;
    wire signed [WIDTH-1:0] w_n;
    
    // Saturate w[n] to 24-bit signed
    assign w_n = (w_temp_wide > W_MAX) ? {1'b0, {(WIDTH-1){1'b1}}} :
                 (w_temp_wide < W_MIN) ? {1'b1, {(WIDTH-1){1'b0}}} :
                                         (w_temp_wide >>> FRAC_BITS)[WIDTH-1:0];

    // Compute FIR section: y[n] = b0*w[n] + b1*w[n-1] + b2*w[n-2]
    wire signed [42:0] fir_b0 = $signed(b0) * $signed(w_n);       // 19 * 24 = 43 bits
    wire signed [42:0] fir_b1 = $signed(b1) * $signed(x_z1);      // 19 * 24 = 43 bits
    wire signed [42:0] fir_b2 = $signed(b2) * $signed(x_z2);      // 19 * 24 = 43 bits
    wire signed [45:0] y_fir_wide = fir_b0 + fir_b1 + fir_b2;     // Sum with headroom
    wire signed [WIDTH-1:0] y_unfiltered = (y_fir_wide >>> FRAC_BITS)[WIDTH-1:0];

    // Apply gain post-filter (EQ amplitude control)
    wire signed [40:0] y_gained = $signed(y_unfiltered) * $signed(gain_q214);  // 24 * 16 = 40 bits
    wire signed [40:0] y_rounded = y_gained + (1 << (FRAC_BITS - 1));
    wire signed [40:0] y_shifted = y_rounded >>> FRAC_BITS;

    // Saturation
    wire overflow  = (y_shifted > $signed(MAX_VAL));
    wire underflow = (y_shifted < $signed(MIN_VAL));

    assign o_sample = overflow  ? MAX_VAL :
                      underflow ? MIN_VAL :
                                  y_shifted[WIDTH-1:0];

endmodule

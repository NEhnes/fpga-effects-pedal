/*==============================================================
 * FUZZ EFFECT MODULE
 *
 * A fuzz/distortion effect for FPGA guitar pedal.
 *
 * Features:
 * - Pre-gain amplification (Q1.14 signed coefficient)
 * - Asymmetric hard clipping (independent +/- thresholds)
 * - 1-pole lowpass tone control (8-bit coefficient)
 * - AXI-Stream handshake with direct backpressure coupling
 *
 * Architecture:
 * - Pre-Gain -> Asymmetric Clip -> Tone LPF -> Output Gain -> Output
 *
 * Output Gain:
 *   Auto-calculated from the average of pos_clip_thresh and neg_clip_thresh.
 *   Rationale: lower clip thresholds produce heavier saturation and higher
 *   perceived loudness (waveform flattens toward square wave). The output
 *   gain compensates by attenuating proportionally, keeping perceived level
 *   more consistent across fuzz settings.
 *
 *   Formula:
 *     avg_thresh   = (pos_clip_thresh + neg_clip_thresh) >> 1  // Q0.16
 *     output_gain  = avg_thresh[15:2]                          // Q1.14 signed
 *
 *   Range: 0x0000 (silence) to 0x3FFF (~0.999× unity)
 *   At heavy clipping (thresholds ≈ 0x4000): gain ≈ 0x1000 (0.25×, -12 dB)
 *   At light clipping (thresholds ≈ 0xE000): gain ≈ 0x3800 (0.875×, -1.2 dB)
 *   At max thresholds (0xFFFF):               gain ≈ 0x3FFF (~unity)
 *
 *==============================================================
 * PARAMETER CONFIGURATION
 *==============================================================
 *
 * pre_gain (16-bit Q1.14 signed)
 *   Absolute range:    0x8000 (-4.0×) to 0x7FFF (+3.9999×)
 *   Usable range:      0xC000 (-1.0×) to 0x6000 (+1.5×)
 *   Unity gain:        0x4000 (1.0×)
 *   Note: Values beyond ±2.0× cause saturation unless input is quiet.
 *         Higher gains useful for aggressive overdrive.
 *
 * pos_clip_thresh (16-bit Q0.16 unsigned)
 *   Absolute range:    0x0000 (clips to 0) to 0xFFFF (nearly no clipping)
 *   Usable range:      0x2000 (+12.5% headroom) to 0xE000 (+87.5% headroom)
 *   Scaled to 24-bit:  0x2000 << 8 to 0xE000 << 8
 *   Note: Controls positive clipping threshold. Set ≥ neg_clip_thresh
 *         for consistent asymmetric character.
 *
 * neg_clip_thresh (16-bit Q0.16 unsigned)
 *   Absolute range:    0x0000 (no negative clipping) to 0xFFFF (maximum clipping)
 *   Usable range:      0x2000 (+12.5% headroom) to 0xE000 (+87.5% headroom)
 *   Scaled to 24-bit:  0x2000 << 8 to 0xE000 << 8
 *   Note: Controls negative clipping threshold. Different values from
 *         pos_clip_thresh create asymmetric fuzz character.
 *
 * tone_coeff (8-bit unsigned)
 *   Absolute range:    0x00 (bypass, brightest) to 0xFF (max filter, darkest)
 *   Usable range:      0x00 to 0xFF (all values valid)
 *   Recommended:       0x00-0x40 (subtle filtering) to 0xA0-0xFF (dark tone)
 *   Note: Only parameter safe across entire register width.
 *         0 = bright/transparent, 255 = maximum lowpass attenuation.
 *==============================================================*/

module fuzz #(
    parameter WIDTH = 24
)(
    // Effect-specific control parameters
    input  wire [15:0] pre_gain,         // Q1.14 signed, unity = 16'h4000
    input  wire [15:0] pos_clip_thresh,  // Q0.16 positive clip threshold
    input  wire [15:0] neg_clip_thresh,  // Q0.16 negative clip threshold
    input  wire [7:0]  tone_coeff,       // 0=bypass (bright), 255=max filter (dark)

    input  wire        tclk,
    input  wire        rst_n,

    // AXI-Stream input
    input  wire [WIDTH-1:0] i_tdata,
    input  wire             i_tvalid,
    output wire             i_tready,

    // AXI-Stream output
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
    wire signed [WIDTH-1:0] gained;
    wire signed [WIDTH-1:0] clipped;
    wire signed [WIDTH-1:0] tone_filtered;
    reg  signed [WIDTH-1:0] tone_z1;  // previous filter state
    wire signed [WIDTH-1:0] gained_out;  // output gain stage result

    //==========================================================
    // Stage 1: Pre-gain (signed Q1.14 multiplication)
    //==========================================================
    sub_gain #(.WIDTH(WIDTH)) gain_stage (
        .i_sample  (i_tdata),
        .gain_q114 (pre_gain),
        .o_sample  (gained)
    );

    //==========================================================
    // Stage 2: Asymmetric hard clipping
    //==========================================================
    sub_clip_asym #(.WIDTH(WIDTH)) clip_stage (
        .i_sample       (gained),
        .pos_clip_q016  (pos_clip_thresh),
        .neg_clip_q016  (neg_clip_thresh),
        .o_sample       (clipped)
    );

    //==========================================================
    // Stage 3: Tone control (1-pole lowpass)
    // y[n] = a*x[n] + (1-a)*y[n-1], a = tone_coeff/256
    //==========================================================
    sub_tone_lpf #(.WIDTH(WIDTH)) tone_stage (
        .i_sample    (clipped),
        .tone_coeff  (tone_coeff),
        .z1          (tone_z1),
        .o_sample    (tone_filtered)
    );

    //==========================================================
    // Stage 4: Output gain (auto-compensation from clip thresholds)
    //
    // Auto-calculate gain coefficient as the average of the two
    // clip thresholds, scaled to Q1.14.
    //   avg = (pos_clip_thresh + neg_clip_thresh) >> 1  (Q0.16)
    //   gain_coeff = {2'b0, avg[15:2]}                   (Q1.14, always ≤ 0.999)
    //
    // At max thresholds (0xFFFF): gain_coeff ≈ 0x3FFF (≈ unity)
    // At heavy clipping (0x4000): gain_coeff ≈ 0x1000 (0.25×)
    //==========================================================
    wire [15:0] outgain_avg = (pos_clip_thresh + neg_clip_thresh) >> 1;
    wire signed [15:0] outgain_coeff = {2'b0, outgain_avg[15:2]};

    sub_gain #(.WIDTH(WIDTH)) outgain_stage (
        .i_sample  (tone_filtered),
        .gain_q114 (outgain_coeff),
        .o_sample  (gained_out)
    );

    //==========================================================
    // Output register — gated by valid handshake
    //==========================================================
    always @(posedge tclk or negedge rst_n) begin
        if (!rst_n) begin
            o_tdata <= {WIDTH{1'b0}};
            tone_z1 <= {WIDTH{1'b0}};
        end else if (i_tvalid && o_tready) begin
            o_tdata   <= gained_out;
            tone_z1   <= tone_filtered;
        end
    end

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
    localparam FRAC_BITS = 14;

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


/*==============================================================
 * SUB-MODULE: sub_clip_asym
 *
 * Asymmetric hard clipping with independent positive and
 * negative thresholds.
 *
 * i_sample       : signed WIDTH-bit input
 * pos_clip_q016  : positive threshold (Q0.16, unsigned)
 * neg_clip_q016  : negative threshold (Q0.16, unsigned)
 * o_sample       : hard-clipped WIDTH-bit output
 *==============================================================*/
module sub_clip_asym #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] i_sample,
    input         [15:0]      pos_clip_q016,
    input         [15:0]      neg_clip_q016,
    output signed [WIDTH-1:0] o_sample
);
    // Scale thresholds from Q0.16 16-bit to WIDTH-bit sample domain
    wire signed [WIDTH-1:0] pos_threshold = pos_clip_q016 <<< (WIDTH - 16);
    wire signed [WIDTH-1:0] neg_threshold = neg_clip_q016 <<< (WIDTH - 16);

    assign o_sample = (i_sample > pos_threshold)  ?  pos_threshold   :
                      (i_sample < -neg_threshold) ? -neg_threshold   :
                                                     i_sample;
endmodule


/*==============================================================
 * SUB-MODULE: sub_tone_lpf
 *
 * 1-pole lowpass filter for tone control.
 * Implements: y[n] = a*x[n] + (1-a)*y[n-1]
 * where a = tone_coeff / 256.
 *
 * tone_coeff = 0   -> bypass (y = x), bright
 * tone_coeff = 255 -> max filtering, dark
 *
 * The caller must register z1 (previous filter output).
 *==============================================================*/
module sub_tone_lpf #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] i_sample,
    input         [7:0]       tone_coeff,
    input  signed [WIDTH-1:0] z1,
    output signed [WIDTH-1:0] o_sample
);
    localparam signed [WIDTH-1:0] MAX_VAL = {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] MIN_VAL = {1'b1, {(WIDTH-1){1'b0}}};

    // Bypass when coefficient is zero
    wire bypass = (tone_coeff == 8'd0);

    wire [8:0] inv_coeff = 9'd256 - {1'b0, tone_coeff};

    // y = (tone_coeff * x + (256 - tone_coeff) * z1) >> 8
    wire signed [WIDTH+8:0] x_term = $signed(i_sample) * $signed({1'b0, tone_coeff});
    wire signed [WIDTH+8:0] z_term = $signed(z1)       * $signed({1'b0, inv_coeff});
    wire signed [WIDTH+8:0] sum    = x_term + z_term;
    wire signed [WIDTH-1:0] filtered = sum >>> 8;

    assign o_sample = bypass                         ? i_sample :
                      (filtered > MAX_VAL)           ? MAX_VAL  :
                      (filtered < MIN_VAL)           ? MIN_VAL  :
                                                       filtered;
endmodule

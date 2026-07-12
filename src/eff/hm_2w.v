/*==============================================================
 * HM-2W METAL DISTORTION EFFECT MODULE
 *
 * Replicates the Boss HM-2W heavy-metal distortion pedal for the
 * Zedboard guitar-pedal pipeline.
 *
 * Features:
 * - Pre-saturation distortion gain (DIST)
 * - Piecewise-linear soft clip + hard ceiling (Ge diode character)
 * - Asymmetric positive/negative bias (crossover asymmetry)
 * - Cascaded dual biquad tone stack (Low @~87 Hz, High @~1 kHz)
 * - Standard vs Custom mode coefficient banks
 * - Final makeup LEVEL gain with saturation
 * - AXI-Stream handshake with direct backpressure coupling
 *
 * Architecture (single-cycle combinational datapath, 1-cycle latch):
 * [Input] -> Dist Gain -> Soft/Hard Clip + Asym
 *        -> Biquad Low (Dry/Wet COLOR_MIX_L)
 *        -> Biquad High (Dry/Wet COLOR_MIX_H)
 *        -> Makeup LEVEL -> [Output reg]
 *
 * Audio: mono signed 24-bit @ ~48 kHz. All DSP is fixed-point.
 * Internal products use 24×16 / 40-bit MAC styles (DSP48 friendly).
 *
 *==============================================================
 * PARAMETER CONFIGURATION
 *==============================================================
 *
 * dist (16-bit Q2.14 unsigned/signed, treated as signed)
 *   Absolute range:  0x0000 (mute path gain) to 0x7FFF (~2.0×)
 *   Usable range:    0x4000 (1.0×) to 0x7800 (~1.875×)
 *   Unity:           0x4000
 *   Note: Pre-clip drive. Higher => more saturation, more harmonics.
 *
 * color_mix_l (16-bit Q2.14)
 *   Absolute range:  0x0000 (dry only) to 0x7FFF (~2.0× wet)
 *   Usable range:    0x2000 (light bass) to 0x6000 (full Low color)
 *   Unity/full wet:  0x4000 blends fully toward Low peaking EQ
 *   Note: Low color-mix pot @ ~87 Hz gyrator/EQ band.
 *
 * color_mix_h (16-bit Q2.14)
 *   Absolute range:  0x0000 (dry) to 0x7FFF
 *   Usable range:    0x2000 to 0x6000
 *   Full wet:        0x4000
 *   Note: High color-mix pot @ ~1 kHz gyrator/EQ band.
 *
 * level (16-bit Q2.14)
 *   Absolute range:  0x0000 (mute) to 0x7FFF (~2.0×)
 *   Usable range:    0x2000 (0.5×) to 0x6000 (1.5×)
 *   Unity:           0x4000
 *   Note: Final volume / makeup after clip+EQ attenuation.
 *
 * mode_select (1-bit)
 *   0 = Standard: original HM-2-ish EQ curve (Low Q~2.0)
 *   1 = Custom:   higher Low Q (~2.5) + small pre-makeup boost
 *
 *==============================================================
 * DESIGN NOTES
 *==============================================================
 * - Soft clip uses a cheap 3-region piecewise map (no exp/log).
 * - Cascaded Direct-Form-I biquads replace analog gyrators.
 * - Coefficient banks are ROM localparams muxed by mode_select.
 * - COLOR_MIX blends dry vs. peaking-EQ wet:
 *     out = dry + mix * (eq - dry)
 * - All registers (biquad delays + o_tdata) update only on
 *   (i_tvalid && o_tready).
 *=============================================================*/

module hm_2w #(
    parameter WIDTH = 24
)(
    // === EFFECT-SPECIFIC CONTROL PARAMETERS ===
    input  wire [15:0] dist,
    input  wire [15:0] color_mix_l,
    input  wire [15:0] color_mix_h,
    input  wire [15:0] level,
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
    // Localparams / thresholds (Q0.16 scaled into sample domain)
    //==========================================================
    localparam [15:0] SOFT_THRESH_Q16 = 16'h3000; // ~18.75% FS soft knee
    localparam [15:0] HARD_THRESH_Q16 = 16'h6000; // ~37.5%  FS hard ceiling
    // Soft-region compression slope k ≈ 0.5 in Q2.14
    localparam signed [15:0] SOFT_SLOPE_Q214 = 16'h2000;
    // Ge-diode style asymmetry: slightly tighter +ve, looser -ve (Q0.16 scale)
    localparam [15:0] POS_HARD_SCALE = 16'hF000; // ~0.9375 of hard thresh
    localparam [15:0] NEG_HARD_SCALE = 16'h1100; // extra ~6.6% for negative
    // Custom mode pre-makeup boost ~ +1.5 dB (≈ 1.19×) in Q2.14
    localparam signed [15:0] CUSTOM_BOOST_Q214 = 16'h4C00;
    localparam signed [15:0] UNITY_Q214        = 16'h4000;

    //==========================================================
    // Internal datapath wires
    //==========================================================
    wire signed [WIDTH-1:0] dist_gained;
    wire signed [WIDTH-1:0] soft_clipped;
    wire signed [WIDTH-1:0] hard_clipped;
    wire signed [WIDTH-1:0] low_eq_raw;
    wire signed [WIDTH-1:0] low_eq_mixed;
    wire signed [WIDTH-1:0] high_eq_raw;
    wire signed [WIDTH-1:0] high_eq_mixed;
    wire signed [WIDTH-1:0] mode_boosted;
    wire signed [WIDTH-1:0] makeup_applied;

    // Biquad delay-line state (Direct-Form I: x[n-1], x[n-2], y[n-1], y[n-2])
    reg signed [WIDTH-1:0] low_x1, low_x2, low_y1, low_y2;
    reg signed [WIDTH-1:0] high_x1, high_x2, high_y1, high_y2;

    //==========================================================
    // Stage 1: Distortion pre-gain
    //==========================================================
    sub_gain_hm2w #(.WIDTH(WIDTH)) u_dist_gain (
        .i_sample (i_tdata),
        .gain_q214(dist),
        .o_sample (dist_gained)
    );

    //==========================================================
    // Stage 2: Soft clip (piecewise-linear) + hard ceiling + asym
    //==========================================================
    sub_soft_hard_clip_hm2w #(.WIDTH(WIDTH)) u_clip (
        .i_sample        (dist_gained),
        .soft_thresh_q16 (SOFT_THRESH_Q16),
        .hard_thresh_q16 (HARD_THRESH_Q16),
        .soft_slope_q214 (SOFT_SLOPE_Q214),
        .pos_hard_scale  (POS_HARD_SCALE),
        .neg_hard_extra  (NEG_HARD_SCALE),
        .o_sample        (hard_clipped)
    );

    // soft_clipped naming reserved if stage split later
    assign soft_clipped = hard_clipped;

    //==========================================================
    // Stage 3: Low biquad (87 Hz peaking) + COLOR_MIX_L blend
    //==========================================================
    sub_biquad_hm2w #(.WIDTH(WIDTH)) u_low_bq (
        .i_sample   (hard_clipped),
        .mode_select(mode_select),
        .is_high    (1'b0),
        .x1         (low_x1),
        .x2         (low_x2),
        .y1         (low_y1),
        .y2         (low_y2),
        .o_sample   (low_eq_raw)
    );

    sub_color_mix_hm2w #(.WIDTH(WIDTH)) u_low_mix (
        .dry        (hard_clipped),
        .wet        (low_eq_raw),
        .mix_q214   (color_mix_l),
        .o_sample   (low_eq_mixed)
    );

    //==========================================================
    // Stage 4: High biquad (1 kHz peaking) + COLOR_MIX_H blend
    //==========================================================
    sub_biquad_hm2w #(.WIDTH(WIDTH)) u_high_bq (
        .i_sample   (low_eq_mixed),
        .mode_select(mode_select),
        .is_high    (1'b1),
        .x1         (high_x1),
        .x2         (high_x2),
        .y1         (high_y1),
        .y2         (high_y2),
        .o_sample   (high_eq_raw)
    );

    sub_color_mix_hm2w #(.WIDTH(WIDTH)) u_high_mix (
        .dry        (low_eq_mixed),
        .wet        (high_eq_raw),
        .mix_q214   (color_mix_h),
        .o_sample   (high_eq_mixed)
    );

    //==========================================================
    // Stage 5: Custom-mode mild pre-makeup boost
    //==========================================================
    wire signed [15:0] boost_gain = mode_select ? CUSTOM_BOOST_Q214 : UNITY_Q214;

    sub_gain_hm2w #(.WIDTH(WIDTH)) u_mode_boost (
        .i_sample (high_eq_mixed),
        .gain_q214(boost_gain),
        .o_sample (mode_boosted)
    );

    //==========================================================
    // Stage 6: Makeup / Level
    //==========================================================
    sub_gain_hm2w #(.WIDTH(WIDTH)) u_makeup (
        .i_sample (mode_boosted),
        .gain_q214(level),
        .o_sample (makeup_applied)
    );

    //==========================================================
    // Output + biquad state — gated by valid handshake
    //==========================================================
    always @(posedge tclk or negedge rst_n) begin
        if (!rst_n) begin
            o_tdata  <= {WIDTH{1'b0}};
            low_x1   <= {WIDTH{1'b0}};
            low_x2   <= {WIDTH{1'b0}};
            low_y1   <= {WIDTH{1'b0}};
            low_y2   <= {WIDTH{1'b0}};
            high_x1  <= {WIDTH{1'b0}};
            high_x2  <= {WIDTH{1'b0}};
            high_y1  <= {WIDTH{1'b0}};
            high_y2  <= {WIDTH{1'b0}};
        end else if (i_tvalid && o_tready) begin
            o_tdata  <= makeup_applied;

            // Low biquad delay line (input = hard_clipped, out = low_eq_raw)
            low_x2   <= low_x1;
            low_x1   <= hard_clipped;
            low_y2   <= low_y1;
            low_y1   <= low_eq_raw;

            // High biquad delay line (input = low_eq_mixed, out = high_eq_raw)
            high_x2  <= high_x1;
            high_x1  <= low_eq_mixed;
            high_y2  <= high_y1;
            high_y1  <= high_eq_raw;
        end
    end

endmodule


/*==============================================================
 * SUB-MODULE: sub_gain_hm2w
 *
 * Signed Q2.14 multiply with round-to-nearest and saturation.
 * Unity = 0x4000. FRAC_BITS = 14.
 *==============================================================*/
module sub_gain_hm2w #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] i_sample,
    input  signed [15:0]      gain_q214,
    output signed [WIDTH-1:0] o_sample
);
    localparam FRAC_BITS = 14;
    localparam signed [WIDTH-1:0] MAX_VAL = {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] MIN_VAL = {1'b1, {(WIDTH-1){1'b0}}};

    wire signed [WIDTH+15:0] prod    = i_sample * gain_q214;
    wire signed [WIDTH+15:0] rounded = prod + (1 <<< (FRAC_BITS - 1));
    wire signed [WIDTH+15:0] shifted = rounded >>> FRAC_BITS;

    assign o_sample = (shifted > MAX_VAL) ? MAX_VAL :
                      (shifted < MIN_VAL) ? MIN_VAL :
                                            shifted[WIDTH-1:0];
endmodule


/*==============================================================
 * SUB-MODULE: sub_soft_hard_clip_hm2w
 *
 * 3-region magnitude clip:
 *   |x| < soft              -> linear
 *   soft ≤ |x| < hard       -> compressed slope toward ceiling
 *   |x| ≥ hard              -> hard clamp
 * Then asymmetric +ve/-ve ceilings for Ge-diode character.
 *==============================================================*/
module sub_soft_hard_clip_hm2w #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] i_sample,
    input         [15:0]      soft_thresh_q16,
    input         [15:0]      hard_thresh_q16,
    input  signed [15:0]      soft_slope_q214,
    input         [15:0]      pos_hard_scale,  // Q0.16 scale of hard thresh (+)
    input         [15:0]      neg_hard_extra,  // Q0.16 extra headroom (-)
    output signed [WIDTH-1:0] o_sample
);
    localparam FRAC_BITS = 14;
    localparam signed [WIDTH-1:0] MAX_VAL = {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] MIN_VAL = {1'b1, {(WIDTH-1){1'b0}}};

    wire signed [WIDTH-1:0] soft_th =
        $signed({1'b0, soft_thresh_q16}) <<< (WIDTH - 16);
    wire signed [WIDTH-1:0] hard_th =
        $signed({1'b0, hard_thresh_q16}) <<< (WIDTH - 16);

    // Asymmetric hard ceilings
    wire signed [WIDTH+15:0] pos_h_prod = hard_th * $signed({1'b0, pos_hard_scale});
    wire signed [WIDTH-1:0]  pos_hard   = pos_h_prod >>> 16;
    wire signed [WIDTH-1:0]  neg_hard   = hard_th +
        ($signed({1'b0, neg_hard_extra}) <<< (WIDTH - 16));

    wire is_neg = i_sample[WIDTH-1];
    wire signed [WIDTH-1:0] abs_x = is_neg ? -i_sample : i_sample;

    // Soft region: soft + slope*(abs - soft)
    wire signed [WIDTH-1:0] over_soft = abs_x - soft_th;
    wire signed [WIDTH+15:0] soft_delta_prod = over_soft * soft_slope_q214;
    wire signed [WIDTH-1:0]  soft_delta = soft_delta_prod >>> FRAC_BITS;
    wire signed [WIDTH-1:0]  soft_val   = soft_th + soft_delta;

    // Select ceiling for this polarity
    wire signed [WIDTH-1:0] ceiling = is_neg ? neg_hard : pos_hard;

    wire signed [WIDTH-1:0] mag_clipped =
        (abs_x < soft_th)  ? abs_x   :
        (abs_x < hard_th)  ? soft_val :
                             ceiling;

    // Guard soft_val if it overshoots ceiling
    wire signed [WIDTH-1:0] mag_sat =
        (mag_clipped > ceiling) ? ceiling : mag_clipped;

    wire signed [WIDTH-1:0] signed_out = is_neg ? -mag_sat : mag_sat;

    assign o_sample = (signed_out > MAX_VAL) ? MAX_VAL :
                      (signed_out < MIN_VAL) ? MIN_VAL :
                                               signed_out;
endmodule


/*==============================================================
 * SUB-MODULE: sub_color_mix_hm2w
 *
 * Dry/wet blend in Q2.14:
 *   o = dry + mix * (wet - dry)
 * mix = 0     -> pure dry
 * mix = 0x4000 → pure wet
 *==============================================================*/
module sub_color_mix_hm2w #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] dry,
    input  signed [WIDTH-1:0] wet,
    input  signed [15:0]      mix_q214,
    output signed [WIDTH-1:0] o_sample
);
    localparam FRAC_BITS = 14;
    localparam signed [WIDTH-1:0] MAX_VAL = {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] MIN_VAL = {1'b1, {(WIDTH-1){1'b0}}};

    wire signed [WIDTH:0] diff_ext = $signed({wet[WIDTH-1], wet}) -
                                     $signed({dry[WIDTH-1], dry});
    wire signed [WIDTH+16:0] scaled = diff_ext * mix_q214;
    wire signed [WIDTH+16:0] shifted = (scaled + (1 <<< (FRAC_BITS - 1)))
                                       >>> FRAC_BITS;
    wire signed [WIDTH:0] sum = $signed({dry[WIDTH-1], dry}) +
                                shifted[WIDTH:0];

    assign o_sample = (sum > MAX_VAL) ? MAX_VAL :
                      (sum < MIN_VAL) ? MIN_VAL :
                                        sum[WIDTH-1:0];
endmodule


/*==============================================================
 * SUB-MODULE: sub_biquad_hm2w
 *
 * Direct-Form I biquad:
 *   y[n] = b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2
 *
 * Coefficients are Q2.14 (signed 16-bit, unity = 0x4000).
 * Two ROM banks × two filters (Low / High), selected by
 * mode_select and is_high.
 *
 * Precomputed for fs = 48 kHz:
 *   Low  Standard:  peaking  87 Hz, Q=2.0,  +12 dB
 *   Low  Custom:    peaking  87 Hz, Q=2.5,  +14 dB
 *   High Standard:  peaking 1 kHz,  Q=3.0,  +12 dB
 *   High Custom:    peaking 1 kHz,  Q=3.0,  +12 dB (+ mode boost elsewhere)
 *==============================================================*/
module sub_biquad_hm2w #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] i_sample,
    input                     mode_select, // 0=std, 1=custom
    input                     is_high,     // 0=low, 1=high
    input  signed [WIDTH-1:0] x1,
    input  signed [WIDTH-1:0] x2,
    input  signed [WIDTH-1:0] y1,
    input  signed [WIDTH-1:0] y2,
    output signed [WIDTH-1:0] o_sample
);
    localparam FRAC_BITS = 14;
    localparam signed [WIDTH-1:0] MAX_VAL = {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] MIN_VAL = {1'b1, {(WIDTH-1){1'b0}}};

    // ---- Coefficient ROM (Q2.14) ----
    // Index encode: {mode_select, is_high}
    // Low std  +12dB @87Hz Q=2.0
    localparam signed [15:0] L_STD_B0 = 16'h4046;
    localparam signed [15:0] L_STD_B1 = 16'h8031; // -1.997
    localparam signed [15:0] L_STD_B2 = 16'h3F8C;
    localparam signed [15:0] L_STD_A1 = 16'h8031;
    localparam signed [15:0] L_STD_A2 = 16'h3FD1;

    // Low cust +14dB @87Hz Q=2.5
    localparam signed [15:0] L_CST_B0 = 16'h4043;
    localparam signed [15:0] L_CST_B1 = 16'h8023;
    localparam signed [15:0] L_CST_B2 = 16'h3F9C;
    localparam signed [15:0] L_CST_A1 = 16'h8023;
    localparam signed [15:0] L_CST_A2 = 16'h3FDF;

    // High std/cust +12dB @1kHz Q=3.0
    localparam signed [15:0] H_STD_B0 = 16'h420F;
    localparam signed [15:0] H_STD_B1 = 16'h8277;
    localparam signed [15:0] H_STD_B2 = 16'h3C90;
    localparam signed [15:0] H_STD_A1 = 16'h8277;
    localparam signed [15:0] H_STD_A2 = 16'h3E9F;

    // Custom High: slightly brighter peak (1.2 kHz, Q=1.2, +9 dB) — more filth
    localparam signed [15:0] H_CST_B0 = 16'h4459;
    localparam signed [15:0] H_CST_B1 = 16'h864D;
    localparam signed [15:0] H_CST_B2 = 16'h36DE;
    localparam signed [15:0] H_CST_A1 = 16'h864D;
    localparam signed [15:0] H_CST_A2 = 16'h3B37;

    reg signed [15:0] b0, b1, b2, a1, a2;

    always @(*) begin
        case ({mode_select, is_high})
            2'b00: begin // Standard Low
                b0 = L_STD_B0; b1 = L_STD_B1; b2 = L_STD_B2;
                a1 = L_STD_A1; a2 = L_STD_A2;
            end
            2'b01: begin // Standard High
                b0 = H_STD_B0; b1 = H_STD_B1; b2 = H_STD_B2;
                a1 = H_STD_A1; a2 = H_STD_A2;
            end
            2'b10: begin // Custom Low
                b0 = L_CST_B0; b1 = L_CST_B1; b2 = L_CST_B2;
                a1 = L_CST_A1; a2 = L_CST_A2;
            end
            default: begin // Custom High
                b0 = H_CST_B0; b1 = H_CST_B1; b2 = H_CST_B2;
                a1 = H_CST_A1; a2 = H_CST_A2;
            end
        endcase
    end

    // MAC: 24 * 16 => 40 bits; accumulate with headroom
    wire signed [WIDTH+15:0] t_b0 = i_sample * b0;
    wire signed [WIDTH+15:0] t_b1 = x1       * b1;
    wire signed [WIDTH+15:0] t_b2 = x2       * b2;
    wire signed [WIDTH+15:0] t_a1 = y1       * a1;
    wire signed [WIDTH+15:0] t_a2 = y2       * a2;

    // y*2^FRAC = b0x + b1x1 + b2x2 - a1y1 - a2y2
    wire signed [WIDTH+18:0] acc =
          $signed({{3{t_b0[WIDTH+15]}}, t_b0})
        + $signed({{3{t_b1[WIDTH+15]}}, t_b1})
        + $signed({{3{t_b2[WIDTH+15]}}, t_b2})
        - $signed({{3{t_a1[WIDTH+15]}}, t_a1})
        - $signed({{3{t_a2[WIDTH+15]}}, t_a2});

    wire signed [WIDTH+18:0] rounded = acc + (1 <<< (FRAC_BITS - 1));
    wire signed [WIDTH+18:0] shifted = rounded >>> FRAC_BITS;

    assign o_sample = (shifted > MAX_VAL) ? MAX_VAL :
                      (shifted < MIN_VAL) ? MIN_VAL :
                                            shifted[WIDTH-1:0];
endmodule

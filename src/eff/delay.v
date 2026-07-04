/*==============================================================
 * DELAY EFFECT MODULE
 *
 * A parametric digital delay effect for FPGA guitar pedal.
 * Uses an inferred block RAM circular buffer for the delay line.
 *
 * Features:
 * - Parametric delay time (0 to MAX_DELAY_SAMPLES-1 samples)
 * - Wet/dry mix control (Q1.14 coefficient)
 * - Regenerative feedback with saturation protection
 * - Makeup gain for output level compensation
 * - AXI-Stream handshake with direct backpressure coupling
 *
 * Architecture:
 * [Input] → (+) → [Delay Line WRITE] → [Delay Line READ] → [Mix] → [Makeup Gain] → [Output]
 *            ↑                                              |
 *            └──── [Feedback Gain] ←─────────────────────────┘
 *
 *==============================================================
 * PARAMETER CONFIGURATION
 *==============================================================
 *
 * delay_time (16-bit unsigned)
 *   Absolute range:    0 to 65535
 *   Usable range:      0 to MAX_DELAY_SAMPLES-1
 *   Unity/Default:     0
 *   Note: Delay in samples at ~48kHz. Each sample ≈ 20.8 µs.
 *         Examples: 2400 samples ≈ 50 ms, 24000 samples ≈ 500 ms.
 *         Values ≥ MAX_DELAY_SAMPLES wrap via truncation.
 *         time=0 gives instantaneous readback (oscillation risk).
 *
 * mix (16-bit Q1.14 signed)
 *   Absolute range:    0x8000 (-4.0×) to 0x7FFF (+3.9999×)
 *   Usable range:      0x0000 (all dry) to 0x4000 (full wet)
 *   Unity/Default:     0x2000 (equal mix)
 *   Note: Applied to wet (delayed) signal only. Dry signal passes
 *         at unity gain. Use makeup_gain to compensate for mix level.
 *
 * feedback (16-bit Q1.14 signed)
 *   Absolute range:    0x8000 (-4.0×) to 0x7FFF (+3.9999×)
 *   Usable range:      0x0000 (no feedback) to 0x3FFF (max stable)
 *   Unity/Default:     0x0000
 *   Note: Controls how much delayed signal feeds back into the
 *         delay line. Values above 0x4000 (1.0×) cause runaway
 *         saturation. Negative values invert polarity of repeats.
 *
 * makeup_gain (16-bit Q1.14 signed)
 *   Same configuration as fuzz module.
 *   Unity/Default:     0x4000 (1.0×)
 *
 *==============================================================
 * TODO
 * - None
 *=============================================================*/

module delay #(
    parameter WIDTH       = 24,
    parameter MAX_DELAY_SAMPLES = 32768  // ~682 ms at 48 kHz
)(
    // === EFFECT-SPECIFIC CONTROL PARAMETERS ===
    input wire [15:0] delay_time,    // delay in samples [0, MAX_DELAY_SAMPLES)
    input wire [15:0] mix,           // Q1.14 wet gain
    input wire [15:0] feedback,      // Q1.14 feedback amount
    input wire [15:0] makeup_gain,   // Q1.14 output level compensation

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
    // Local parameters
    //==========================================================
    localparam ADDR_W = 15;  // 2^15 = 32768

    //==========================================================
    // Delay line BRAM
    //==========================================================
    reg  [WIDTH-1:0] delay_line [0:MAX_DELAY_SAMPLES-1];
    reg  [ADDR_W-1:0] wr_ptr;
    wire [ADDR_W-1:0] rd_addr;
    reg  signed [WIDTH-1:0] rd_data;

    // BRAM and rd_data initialisation — simulation only.
    // Avoids X-propagation from uninitialized memory and registered
    // read output through the feedback multiplier (X * 0 = X in Verilog).
    // Real BRAM powers up as zero with registered output = 0.
    integer init_i;
    initial begin
        rd_data = {WIDTH{1'b0}};
        for (init_i = 0; init_i < MAX_DELAY_SAMPLES; init_i = init_i + 1)
            delay_line[init_i] = {WIDTH{1'b0}};
    end

    //==========================================================
    // Internal signals
    //==========================================================
    wire signed [WIDTH-1:0] fb_scaled;    // feedback * delayed sample
    wire signed [WIDTH-1:0] wr_data;      // data to write to delay line
    wire signed [WIDTH-1:0] wet_scaled;   // mix * delayed sample
    wire signed [WIDTH-1:0] mix_sum;      // dry + wet (with saturation)
    wire signed [WIDTH-1:0] makeup_applied;

    //==========================================================
    // Read address computation (combinational)
    //
    // rd_addr = wr_ptr - delay_time, with wraparound at
    // MAX_DELAY_SAMPLES. Relies on unsigned subtraction
    // wrapping via power-of-2 modulo when delay_time is
    // truncated to ADDR_W bits.
    //==========================================================
    assign rd_addr = wr_ptr - delay_time[ADDR_W-1:0];

    //==========================================================
    // Delay line BRAM read (registered, continuous)
    //
    // The registered read gives 1-cycle latency from address
    // to data. This is inherent to BRAM and handled by the
    // pipeline: rd_data in cycle N corresponds to the read
    // address from cycle N-1.
    //==========================================================
    always @(posedge tclk) begin
        rd_data <= delay_line[rd_addr];
    end

    //==========================================================
    // Stage 1: Feedback gain
    // rd_data * feedback (Q1.14), saturated
    //==========================================================
    sub_gain #(.WIDTH(WIDTH)) feedback_gain (
        .i_sample  (rd_data),
        .gain_q114 (feedback),
        .o_sample  (fb_scaled)
    );

    //==========================================================
    // Stage 2: Saturating add for delay line write data
    // wr_data = i_tdata + fb_scaled (with saturation)
    //==========================================================
    sub_sat_add #(.WIDTH(WIDTH)) feedback_adder (
        .a     (i_tdata),
        .b     (fb_scaled),
        .o_sum (wr_data)
    );

    //==========================================================
    // Stage 3: Wet gain
    // rd_data * mix (Q1.14), saturated
    //==========================================================
    sub_gain #(.WIDTH(WIDTH)) wet_gain (
        .i_sample  (rd_data),
        .gain_q114 (mix),
        .o_sample  (wet_scaled)
    );

    //==========================================================
    // Stage 4: Saturating add for dry/wet mix
    // mix_sum = i_tdata + wet_scaled (with saturation)
    //==========================================================
    sub_sat_add #(.WIDTH(WIDTH)) mix_adder (
        .a     (i_tdata),
        .b     (wet_scaled),
        .o_sum (mix_sum)
    );

    //==========================================================
    // Stage 5: Makeup gain
    //==========================================================
    sub_gain #(.WIDTH(WIDTH)) makeup_stage (
        .i_sample  (mix_sum),
        .gain_q114 (makeup_gain),
        .o_sample  (makeup_applied)
    );

    //==========================================================
    // Output register & delay line write — gated by handshake
    //==========================================================
    always @(posedge tclk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr  <= {ADDR_W{1'b0}};
            o_tdata <= {WIDTH{1'b0}};
        end else if (i_tvalid && o_tready) begin
            // Write feedback-mixed sample to current write position
            delay_line[wr_ptr] <= wr_data;

            // Advance write pointer (wraps at MAX_DELAY_SAMPLES)
            if (wr_ptr == MAX_DELAY_SAMPLES-1)
                wr_ptr <= {ADDR_W{1'b0}};
            else
                wr_ptr <= wr_ptr + 1'b1;

            // Output register
            o_tdata <= makeup_applied;
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


/*==============================================================
 * SUB-MODULE: sub_sat_add
 *
 * Signed saturating addition.
 * Prevents wraparound distortion when summing two audio signals.
 *
 * a, b     : signed WIDTH-bit audio samples
 * o_sum    : saturated WIDTH-bit sum
 *==============================================================*/
module sub_sat_add #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] a,
    input  signed [WIDTH-1:0] b,
    output signed [WIDTH-1:0] o_sum
);
    localparam signed [WIDTH-1:0] MAX_VAL = {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] MIN_VAL = {1'b1, {(WIDTH-1){1'b0}}};

    wire signed [WIDTH:0] temp = $signed(a) + $signed(b);

    assign o_sum = (temp > MAX_VAL) ? MAX_VAL :
                   (temp < MIN_VAL) ? MIN_VAL :
                                      temp[WIDTH-1:0];
endmodule
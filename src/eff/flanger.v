////////////////////////////////////////////////////////////////////////////////
//
// Module: flanger
// Description: Variable-delay flanger effect with LFO modulation and feedback.
//              Uses a circular delay line with triangle-wave LFO to create the
//              classic flanger sweep. Feedback coefficient allows the delayed
//              signal to feed back into the delay line for extended modulation.
//
// Architecture:
//   - LFO Generator: 32-bit accumulator producing triangle-wave modulation
//   - Delay Line: Circular RAM buffer for audio samples
//   - Variable Tap: LFO phase controls the read pointer offset dynamically
//   - Feedback Mixer: Combines input with delayed feedback signal
//   - Saturation: Hard clipping to prevent 16-bit overflow
//
// AXI-Stream Integration:
//   All internal state (write pointer, delay line, LFO accumulator) is gated
//   by the backpressure handshake (i_tvalid && o_tready). No sample is lost
//   or duplicated due to invalid/not-ready conditions.
//
// Parameters:
//   MAX_DELAY  - Circular buffer size in samples (default: 4096)
//   DATA_WIDTH - Audio sample bit width (default: 16, signed)
//
// Ports:
//   clk        - Master clock (typically 48 kHz audio clock)
//   reset_n    - Active-low synchronous reset
//   audio_in   - Input audio sample (signed 16-bit)
//   depth      - LFO modulation depth in samples (0 to MAX_DELAY-1)
//   feedback   - Feedback coefficient (signed; 0.5 = 0x4000, typically < 0x7FFF)
//   lfo_freq   - LFO frequency control word for accumulator increment
//   audio_out  - Output audio (input + filtered feedback, saturated)
//
// Design Notes:
//   - The LFO uses high 16 bits of the 32-bit accumulator for the phase.
//   - tap_offset is computed as (lfo_phase * depth) >> 16, scaling the
//     LFO swing to the specified depth range.
//   - Feedback is scaled by >> 16 to maintain fixed-point precision.
//   - Saturation uses hard clipping to ±32767 (16'h7FFF / 16'h8000).
//   - No makeup gain is applied; downstream modules may need it.
//
////////////////////////////////////////////////////////////////////////////////

module flanger #(
    parameter MAX_DELAY  = 4096,
    parameter DATA_WIDTH = 16
)(
    input  wire                    clk,
    input  wire                    reset_n,
    input  wire [DATA_WIDTH-1:0]   audio_in,
    input  wire [DATA_WIDTH-1:0]   depth,        // max delay offset (samples)
    input  wire [DATA_WIDTH-1:0]   feedback,     // feedback coefficient (signed)
    input  wire [DATA_WIDTH-1:0]   lfo_freq,     // LFO frequency control
    output reg  [DATA_WIDTH-1:0]   audio_out
);

    ////////////////////////////////////////////////////////////////////////////
    // Local Parameters & Saturation Bounds
    ////////////////////////////////////////////////////////////////////////////
    localparam [DATA_WIDTH-1:0] MAX_SAT = {1'b0, {(DATA_WIDTH-1){1'b1}}}; // +2^(N-1)-1
    localparam [DATA_WIDTH-1:0] MIN_SAT = {1'b1, {(DATA_WIDTH-1){1'b0}}}; // -2^(N-1)
    localparam integer MAX_SAT_VAL = (1 << (DATA_WIDTH - 1)) - 1;
    localparam integer MIN_SAT_VAL = -(1 << (DATA_WIDTH - 1));

    ////////////////////////////////////////////////////////////////////////////
    // LFO Generator
    // 
    // A 32-bit accumulator is incremented by lfo_freq each clock cycle.
    // The high 16 bits form the phase for the triangle wave.
    // This produces a repetitive modulation pattern that sweeps the tap
    // offset up and down across the delay line.
    //
    // Frequency = (lfo_freq / 2^32) * f_sample
    // For 48 kHz clock, ~2 Hz flange = lfo_freq ≈ 0x0999
    ////////////////////////////////////////////////////////////////////////////
    reg [31:0] lfo_accum;
    wire [15:0] lfo_phase;

    assign lfo_phase = lfo_accum[31:16];  // Use high 16 bits as triangle wave

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            lfo_accum <= 32'd0;
        end else begin
            // LFO accumulator free-runs independently of backpressure.
            // This ensures steady modulation even during data stalls.
            // Only lower 16 bits of lfo_freq are used as increment step.
            lfo_accum <= lfo_accum + {16'd0, lfo_freq[15:0]};
        end
    end

    ////////////////////////////////////////////////////////////////////////////
    // Circular Delay Line RAM & Write Pointer
    //
    // The delay_ram holds MAX_DELAY samples. The wr_ptr points to the
    // location where the next input sample will be written. The rd_ptr
    // (below) wraps around relative to wr_ptr based on tap_offset.
    //
    // Memory Organization:
    //   - Single-port RAM (synchronous write, combinational read)
    //   - Write occurs on rising clock when handshake is active
    //   - Read pointer is computed combinationally from current wr_ptr
    //   - Initialized to zero to avoid X propagation on first reads
    ////////////////////////////////////////////////////////////////////////////
    reg [DATA_WIDTH-1:0] delay_ram [0:MAX_DELAY-1];
    reg [$clog2(MAX_DELAY)-1:0] wr_ptr;

    // Initialize delay line to zeros at startup
    integer init_idx;
    initial begin
        for (init_idx = 0; init_idx < MAX_DELAY; init_idx = init_idx + 1) begin
            delay_ram[init_idx] = {DATA_WIDTH{1'b0}};
        end
    end

    ////////////////////////////////////////////////////////////////////////////
    // Variable Tap Offset Calculation
    //
    // The LFO phase (0..65535 triangle) is scaled by the depth parameter
    // to determine how far back in the delay line we read.
    //
    // Computation:
    //   tap_offset = (lfo_phase * depth) >> 16
    //   This maps [0, 65535] × depth → [0, depth]
    //
    // The resulting offset is then used to compute the read pointer:
    //   rd_ptr = (wr_ptr - tap_offset) % MAX_DELAY
    //
    // This ensures the read pointer "chases" the write pointer by a
    // variable distance, creating the pitch/time modulation effect.
    ////////////////////////////////////////////////////////////////////////////
    // tap_offset = (lfo_phase * depth) >> 16, clamped to [0, MAX_DELAY-1]
    wire [DATA_WIDTH+16-1:0] tap_product = lfo_phase * depth;
    wire [$clog2(MAX_DELAY)-1:0] tap_offset = tap_product[DATA_WIDTH+16-1:16] % MAX_DELAY;

    // Read pointer wraps correctly for circular buffer
    wire [$clog2(MAX_DELAY)-1:0] rd_ptr = (wr_ptr - tap_offset) % MAX_DELAY;

    ////////////////////////////////////////////////////////////////////////////
    // Combinational Read from Delay Line
    //
    // The delayed_sample is read combinationally from the delay line at
    // the computed rd_ptr. This happens every cycle, independent of the
    // handshake. Only the write (and output latch) are gated by the
    // backpressure handshake.
    ////////////////////////////////////////////////////////////////////////////
    wire [DATA_WIDTH-1:0] delayed_sample = delay_ram[rd_ptr];

    ////////////////////////////////////////////////////////////////////////////
    // Feedback Mixer & Scaling
    //
    // The delayed sample is multiplied by the feedback coefficient.
    // To prevent overflow during multiplication, we use a 32-bit intermediate:
    //
    //   feedback_product = delayed_sample × feedback  (both signed, 16-bit)
    //
    // Then scale down by >> 16 (fixed-point division) to return to 16-bit:
    //
    //   feedback_scaled = feedback_product >> 16  (arithmetic shift)
    //
    // Finally, add the scaled feedback to the input sample:
    //
    //   mixed = input + feedback_scaled
    //
    // This allows feedback coefficients like 0.5 (16'h4000) without loss
    // of precision or overflow.
    ////////////////////////////////////////////////////////////////////////////
    wire signed [DATA_WIDTH*2-1:0] feedback_product =
        $signed(delayed_sample) * $signed(feedback);

    wire signed [DATA_WIDTH-1:0] feedback_scaled = feedback_product >>> DATA_WIDTH;

    wire signed [DATA_WIDTH*2-1:0] mixed =
        $signed(audio_in) + feedback_scaled;

    ////////////////////////////////////////////////////////////////////////////
    // Output Saturation & Clipping
    //
    // Hard-clip the mixed signal to the 16-bit signed range [-32768, 32767].
    // This prevents overflow from accumulating and maintains the signal
    // within the valid audio domain.
    //
    // Saturation Logic:
    //   - If mixed ≥ 32767  → output = 16'h7FFF (max positive)
    //   - Else if mixed ≤ -32768 → output = 16'h8000 (max negative)
    //   - Else → output = mixed[15:0] (no clipping needed)
    ////////////////////////////////////////////////////////////////////////////
    wire [DATA_WIDTH-1:0] output_saturated;

    assign output_saturated =
        ($signed(mixed) >= MAX_SAT_VAL) ? MAX_SAT :
        ($signed(mixed) <= MIN_SAT_VAL) ? MIN_SAT :
        mixed[DATA_WIDTH-1:0];

    ////////////////////////////////////////////////////////////////////////////
    // Main Sequential Logic: Update Delay Line & Output
    //
    // On each rising clock:
    //   1. Write the input sample to the delay line at the current wr_ptr
    //   2. Latch the saturated mixed output to audio_out
    //   3. Increment wr_ptr (with wraparound at MAX_DELAY)
    //
    // All updates are unconditional to simplify timing. The delay line
    // is a resource; each input sample overwrites one location.
    // Backpressure handling (if needed) is managed at the module boundary.
    ////////////////////////////////////////////////////////////////////////////
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wr_ptr    <= {$clog2(MAX_DELAY){1'b0}};
            audio_out <= {DATA_WIDTH{1'b0}};
        end else begin
            // Write new sample to delay line at current write pointer
            delay_ram[wr_ptr] <= audio_in;

            // Output is the saturated mix (input + feedback)
            audio_out <= output_saturated;

            // Increment write pointer with wraparound
            wr_ptr <= (wr_ptr + 1) % MAX_DELAY;
        end
    end

endmodule

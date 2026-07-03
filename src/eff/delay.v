/*
 * delay_effect.v
 *
 * Digital delay effect with ring buffer, feedback path, and dry/wet mix.
 * All gain parameters in Q1.14 fixed-point (unity = 16'h4000).
 *
 * Signal flow per sample:
 *   1. Apply input_gain to incoming sample
 *   2. Read delayed sample from ring buffer at read_ptr
 *   3. Compute feedback: delayed * feedback_q114 (with saturation)
 *   4. Write to buffer: gained_input + feedback (with saturation)
 *   5. Mix output: (input * dry_gain) + (delayed * wet_gain) (with saturation)
 *   6. Advance write_ptr
 *
 * AXI-Stream: valid/ready handshake propagated combinatorially (passthrough).
 * DEPTH must be a power of 2 for wraparound via bitmask.
 *
 * Reset: active-low, asynchronous (matches existing codebase convention)
 */

module delay_effect #(
    parameter WIDTH = 24,
    parameter DEPTH = 1024  // Must be power of 2
)(
    // Effect parameters
    input  wire [15:0] delay_samples,      // Integer: 1 to DEPTH
    input  wire [15:0] feedback_q114,      // Q1.14
    input  wire [15:0] wet_gain_q114,      // Q1.14
    input  wire [15:0] dry_gain_q114,      // Q1.14
    input  wire [15:0] input_gain_q114,    // Q1.14

    // AXI-Stream
    input  wire        tclk,
    input  wire        rst_n,
    input  wire [WIDTH-1:0] i_tdata,
    input  wire             i_tvalid,
    output wire             i_tready,
    input  wire             o_tready,
    output wire             o_tvalid,
    output reg  [WIDTH-1:0] o_tdata
);

// AXI-Stream passthrough
assign i_tready = o_tready;
assign o_tvalid = i_tvalid;

// ======= RING BUFFER =======
localparam integer PTR_WIDTH = $clog2(DEPTH);
localparam [PTR_WIDTH-1:0] PTR_MASK = DEPTH[PTR_WIDTH-1:0] - 1'b1;

reg [WIDTH-1:0]      ring_buf [0:DEPTH-1];
reg [PTR_WIDTH-1:0]  write_ptr;

wire [PTR_WIDTH-1:0] read_ptr;
wire [WIDTH-1:0]     delayed_sample;

// read_ptr = write_ptr - delay_samples (wraparound via bitmask)
assign read_ptr = (write_ptr - (delay_samples[PTR_WIDTH-1:0] & PTR_MASK)) & PTR_MASK;
assign delayed_sample = ring_buf[read_ptr];

// ======= SIGNAL PROCESSING =======
wire signed [WIDTH-1:0] gained_input;
wire signed [WIDTH-1:0] feedback_signal;
wire signed [WIDTH-1:0] write_value;
wire signed [WIDTH-1:0] dry_signal;
wire signed [WIDTH-1:0] wet_signal;
wire signed [WIDTH-1:0] mix_output;

sub_gain #(.WIDTH(WIDTH)) u_input_gain (
    .i_sample(i_tdata),
    .gain_q114(input_gain_q114),
    .o_sample(gained_input)
);

sub_gain #(.WIDTH(WIDTH)) u_feedback_gain (
    .i_sample(delayed_sample),
    .gain_q114(feedback_q114),
    .o_sample(feedback_signal)
);

sub_gain #(.WIDTH(WIDTH)) u_dry_gain (
    .i_sample(i_tdata),
    .gain_q114(dry_gain_q114),
    .o_sample(dry_signal)
);

sub_gain #(.WIDTH(WIDTH)) u_wet_gain (
    .i_sample(delayed_sample),
    .gain_q114(wet_gain_q114),
    .o_sample(wet_signal)
);

sub_add #(.WIDTH(WIDTH)) u_feedback_add (
    .i_a(gained_input),
    .i_b(feedback_signal),
    .o_sum(write_value)
);

sub_add #(.WIDTH(WIDTH)) u_mix_add (
    .i_a(dry_signal),
    .i_b(wet_signal),
    .o_sum(mix_output)
);

// ======= MAIN SEQUENTIAL LOGIC =======
integer i;

always @(posedge tclk or negedge rst_n) begin
    if (!rst_n) begin
        write_ptr <= {PTR_WIDTH{1'b0}};
        o_tdata   <= {WIDTH{1'b0}};
        // Initialize ring buffer to zero on reset
        for (i = 0; i < DEPTH; i = i + 1) begin
            ring_buf[i] <= {WIDTH{1'b0}};
        end
    end else if (i_tvalid && o_tready) begin
        ring_buf[write_ptr] <= write_value;
        write_ptr <= (write_ptr + 1'b1) & PTR_MASK;
        o_tdata <= mix_output;
    end
end

endmodule


/*=========== sub-module gain ============
 * Uses fixed point math
 * Signed WIDTH-bit audio sample
 * Signed Q1.14 gain value
 *======================================*/
module sub_gain #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] i_sample,
    input  signed [15:0] gain_q114,  // SIGNED Q1.14, unity gain = 0x4000
    output signed [WIDTH-1:0] o_sample
);
    localparam FRAC_BITS = 14;
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

/*=========== sub-module add ============
 * Saturating signed addition.
 * Clamps to [-(2^(WIDTH-1)), 2^(WIDTH-1)-1] on overflow/underflow.
 *======================================*/
module sub_add #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] i_a,
    input  signed [WIDTH-1:0] i_b,
    output signed [WIDTH-1:0] o_sum
);
    wire signed [WIDTH:0] sum_ext = {i_a[WIDTH-1], i_a} + {i_b[WIDTH-1], i_b};

    localparam signed [WIDTH-1:0] MAX_VAL = {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] MIN_VAL = {1'b1, {(WIDTH-1){1'b0}}};

    wire overflow = (sum_ext[WIDTH] != sum_ext[WIDTH-1]);

    assign o_sum = overflow ? (sum_ext[WIDTH] ? MAX_VAL : MIN_VAL) :
                              sum_ext[WIDTH-1:0];
endmodule
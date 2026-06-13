/*
 * EXTENSIONS TO THIS EFFECT
 * - Output gain
 * - Asymmetric +/- clipping
 * - Dry/wet mix
 */

module hard_clip #(
    parameter WIDTH = 24
)(
    // effect-specific parameters
    input  wire [15:0] _input_gain,
    input  wire [15:0] _normalized_clip,


    input  wire        tclk,
    input  wire        rst_n,

    // Incoming
    input  wire [WIDTH-1:0] i_tdata,
    input  wire             i_tvalid,
    output wire             i_tready,

    // Outgoing
    input  wire             o_tready,
    output wire             o_tvalid,
    output reg  [WIDTH-1:0] o_tdata
);

// AXI-Stream handshake propagation
// this allows endpoints to effectively communicate together
// everything in the middle will be reliable on clock cycle, no axi logic needed
assign i_tready = o_tready;
assign o_tvalid = i_tvalid;

wire [WIDTH-1:0] processed;

//=========== MY SHIT ============

wire [15:0] input_gain;
wire [15:0] normalized_clip;

// set undefined paramaters as unity (no effect)
assign input_gain = (_input_gain === 16'bx) ? 16'h0001 : _input_gain;
assign normalized_clip = (_normalized_clip === 16'bx) ? 16'h0001 : _normalized_clip;


wire [WIDTH-1:0] s1s2;

sub_gain s1 (
    .i_sample(i_tdata),
    .gain_q114(input_gain),
    .o_sample(s1s2)
);

sub_clip s2 (
    .i_sample(s1s2),
    .clip_q016(normalized_clip),
    .o_sample(processed)
);


//================================

always @(posedge tclk or negedge rst_n) begin

    // clear bad data on reset
    if (!rst_n) begin
        o_tdata <= {WIDTH{1'b0}};
    end 
    
    else if (i_tvalid && o_tready) begin
        // register updates when send and receive are good
        o_tdata <= processed;
    end
end
endmodule





/*=========== sub-module gain ============
 * Uses fixed point math
 * Signed 24-bit audio sample
 * Signed Q1.14 gain value
 * Compute truncated value
 *======================================*/
module sub_gain #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] i_sample,
    input  signed [15:0] gain_q114,  // SIGNED Q1.14, unity gain = 0x4000 btw
    output signed [WIDTH-1:0] o_sample
);
    localparam FRAC_BITS = 14;
    wire signed [(WIDTH + 16) - 1:0] temp;
    assign temp = i_sample * gain_q114;

    wire signed [(WIDTH + 16) - 1:0] rounded = temp + (1 << (FRAC_BITS - 1)); // round product
    assign o_sample = rounded >>> FRAC_BITS; // logical shift to preserve sign
endmodule

module sub_clip #(
    parameter WIDTH = 24
)(
    input  signed [WIDTH-1:0] i_sample,
    input         [15:0] clip_q016,  // Q0.15 (+/- 1.0)
    output signed [WIDTH-1:0] o_sample
);
    // Scale threshold from 16-bit Q0.15 up to WIDTH-bit sample domain
    wire signed [WIDTH-1:0] threshold = clip_q016 <<< (WIDTH - 16);
    
    wire signed [WIDTH-1:0] clamped_high = (i_sample > threshold) ? threshold : i_sample;
    assign o_sample = (clamped_high < -threshold) ? -threshold : clamped_high;
endmodule







// module gain(A, CLK, D);

//     input [7:0] A;
//     input CLK;
//     reg [15:0] W; // reg instead of wire, wire cannot hold value
//     output reg [7:0] D;

//     localparam SCALE = 8'd2; // 8 bits, decimal, value 2

//     always@(posedge CLK)
//     begin
//         // non blocking holds the output until a predictable time
//         // dont use assign here, assign is for combinational logic.
//         // think of assign like wiring things together
//         // must use registers, as wires cannot hold values, just transfer data in real-time
//         W <= A * SCALE; // multiply by constant
//         D <= (W > 16'd255) ? 8'd255 : W[7:0]; // cap & truncate
//     end
// endmodule
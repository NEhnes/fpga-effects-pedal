/*
 * EXTENSIONS TO THIS EFFECT
 * - Output gain
 * - Asymmetric +/- clipping
 * - Dry/wet mix
 */

module hard_clip #(
    parameter WIDTH = 24,
    parameter INPUT_GAIN = 1.15,
    parameter ABS_CLIP_THRESHOLD = 1
)(
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
    input  signed [15:0] gain_q115,  // Q1.15, unity gain = 0x8000 btw
    output signed [WIDTH-1:0] o_sample
);
    localparam FRAC_BITS = 15;
    wire signed [(WIDTH + 16) - 1:0] temp;
    assign temp = i_sample * gain_q115;
    // round product, then shift
    wire signed [(WIDTH + 16) - 1:0] rounded = temp + (1 << (FRAC_BITS - 1));
    assign o_sample = rounded >>> FRAC_BITS;
endmodule

// module sub_clip ()
// endmodule







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
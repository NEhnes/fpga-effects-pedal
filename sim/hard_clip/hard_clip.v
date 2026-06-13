/*
 * EXTENSIONS TO THIS EFFECT
 * - Output gain
 * - Asymmetric +/- clipping
 * - Dry/wet mix
 */

module passthrough #(
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

//========================





//========================

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
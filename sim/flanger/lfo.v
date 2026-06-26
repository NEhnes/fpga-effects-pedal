// LFO generator module
module lfo (
    input  wire        clk,
    input  wire        reset,
    input  wire [15:0] freq_ctrl,   // frequency control (0‑65535 maps to 0‑10 Hz)
    output reg  [15:0] phase_out    // signed phase output used as delay offset
);
    // Simple N‑bit phase accumulator
    reg [31:0] accum;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            accum <= 32'd0;
            phase_out <= 16'd0;
        end else begin
            accum <= accum + {16'd0, freq_ctrl}; // add frequency control each cycle
            // Use high 16 bits as a triangle LFO
            phase_out <= accum[31:16];
        end
    end
endmodule

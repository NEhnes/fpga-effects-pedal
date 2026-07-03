// Flanger effect module (fixed)
// Uses variable-delay line with LFO modulation
module flanger #(
    parameter MAX_DELAY = 4096,
    parameter DATA_WIDTH = 16
)(
    input  wire                    clk,
    input  wire                    reset_n,
    input  wire [DATA_WIDTH-1:0]   audio_in,
    input  wire [DATA_WIDTH-1:0]   depth,        // max delay offset (samples)
    input  wire [DATA_WIDTH-1:0]   feedback,     // feedback coefficient (0-32767)
    input  wire [DATA_WIDTH-1:0]   lfo_freq,     // LFO frequency control
    output reg  [DATA_WIDTH-1:0]   audio_out
);

    localparam [DATA_WIDTH-1:0] MAX_SAT = 16'h7FFF;
    localparam [DATA_WIDTH-1:0] MIN_SAT = 16'h8000;

    // ===== LFO Generator =====
    reg [31:0] lfo_accum;
    wire [15:0] lfo_phase;
    
    assign lfo_phase = lfo_accum[31:16];  // Use high 16 bits as triangle wave
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            lfo_accum <= 32'd0;
        end else begin
            lfo_accum <= lfo_accum + {16'd0, lfo_freq};
        end
    end

    // ===== Delay Line RAM =====
    reg [DATA_WIDTH-1:0] delay_ram [0:MAX_DELAY-1];
    reg [$clog2(MAX_DELAY)-1:0] wr_ptr;

    // ===== Compute variable tap offset =====
    // tap_offset = (lfo_phase * depth) >> 16
    wire [31:0] tap_product = {16'd0, lfo_phase} * {16'd0, depth};
    wire [$clog2(MAX_DELAY)-1:0] tap_offset = tap_product[31:16] % MAX_DELAY;
    
    // Read pointer: wr_ptr - tap_offset (wrapping)
    wire [$clog2(MAX_DELAY)-1:0] rd_ptr = (wr_ptr - tap_offset) % MAX_DELAY;
    
    // Combinational read from delay line
    wire [DATA_WIDTH-1:0] delayed_sample = delay_ram[rd_ptr];

    // ===== Mix: original + (delayed * feedback) >> 16 =====
    // Use larger intermediate to prevent overflow
    wire signed [DATA_WIDTH*2-1:0] feedback_product = 
        $signed(delayed_sample) * $signed(feedback);
    wire signed [DATA_WIDTH*2-1:0] feedback_scaled = feedback_product >>> 16;
    wire signed [DATA_WIDTH*2-1:0] mixed = 
        $signed(audio_in) + feedback_scaled;
    
    // Saturate output to 16-bit signed range
    // Hard clipping: clamp to ±32767
    wire [DATA_WIDTH-1:0] output_saturated;
    assign output_saturated = 
        (mixed >= 32767) ? 16'h7FFF :
        (mixed <= -32768) ? 16'h8000 :
        mixed[DATA_WIDTH-1:0];

    // ===== Main logic: update delay line and output =====
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wr_ptr <= {$clog2(MAX_DELAY){1'b0}};
            audio_out <= 16'sd0;
        end else begin
            // Write new sample to delay line at write pointer
            delay_ram[wr_ptr] <= audio_in;
            
            // Output is the mixed result (original + feedback)
            audio_out <= output_saturated;
            
            // Increment write pointer
            wr_ptr <= (wr_ptr + 1) % MAX_DELAY;
        end
    end

endmodule
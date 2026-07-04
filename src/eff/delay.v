`timescale 1ns / 1ps

/*==============================================================
 * DELAY EFFECT MODULE
 *
 * A mono delay/echo effect for FPGA guitar pedal platform.
 * 
 * Features:
 *   - Circular buffer delay line (configurable, up to 96k samples)
 *   - Variable delay time in samples
 *   - Wet/dry mix parameter (0=dry, 255=wet)
 *   - Feedback loop for repeating echoes
 *   - AXI-Stream handshake with cycle-accurate backpressure
 *   - 4-stage pipeline to absorb BRAM read latency
 *
 * Architecture:
 *   Input -> [Stage 1: BRAM read] -> [Stage 2: propagate]
 *         -> [Stage 3: align input] -> [Stage 4: mix & writeback]
 *         -> Output register
 *
 * Parameters:
 *   WIDTH              : Sample bit-width (default 24)
 *   MAX_DELAY_SAMPLES  : Delay buffer size in samples (default 96000)
 *   ADDR_WIDTH         : Address bits for delay buffer (default 17)
 *
 *==============================================================*/

module delay #(
    parameter WIDTH = 24,
    parameter MAX_DELAY_SAMPLES = 96000,
    parameter ADDR_WIDTH = 17
) (
    // System clock and reset
    input  wire                  tclk,
    input  wire                  rst_n,

    // AXI-Stream input (slave)
    input  wire                  i_tvalid,
    output wire                  i_tready,
    input  wire [WIDTH-1:0]      i_tdata,

    // AXI-Stream output (master)
    output wire                  o_tvalid,
    input  wire                  o_tready,
    output wire [WIDTH-1:0]      o_tdata,

    // Effect control parameters
    input  wire [ADDR_WIDTH-1:0] delay_samples,  // Delay time (0 to MAX_DELAY_SAMPLES-1)
    input  wire [7:0]            mix,             // Mix blend (0=dry, 128=50%, 255=wet)
    input  wire [7:0]            feedback         // Feedback amount (0-255)
);

    /*==============================================================
     * AXI-Stream Handshake
     *
     * Direct combinational coupling of ready/valid signals.
     * Data transfers only when i_tvalid && o_tready.
     * All internal state updates gated by this condition.
     *==============================================================*/
    assign i_tready = o_tready;
    assign o_tvalid = i_tvalid;

    /*==============================================================
     * Delay Line Memory (Circular Buffer)
     *
     * Block RAM storing delayed samples.
     * write_ptr: current write position (auto-incremented each cycle)
     * read_ptr:  derived from write_ptr and delay_samples parameter
     *==============================================================*/
    reg  signed [WIDTH-1:0] delay_mem [0:MAX_DELAY_SAMPLES-1];
    reg  [ADDR_WIDTH-1:0]   write_ptr;

    /*==============================================================
     * Read Pointer Calculation
     *
     * Computes read address as: write_ptr - delay_samples
     * with modulo wraparound to handle circular buffer.
     *==============================================================*/
    wire [ADDR_WIDTH-1:0] read_ptr;
    assign read_ptr = (write_ptr >= delay_samples) ?
                      (write_ptr - delay_samples) :
                      (write_ptr + MAX_DELAY_SAMPLES - delay_samples);

    /*==============================================================
     * Pipeline Stages
     *
     * p1_delayed : Stage 1 output — BRAM read result
     * p2_delayed : Stage 2 output — propagation
     * p3_input   : Stage 3 output — latched dry input
     * p3_delayed : Stage 3 output — propagated wet sample
     * p4_output  : Stage 4 output — mixed result
     *
     * This pipeline structure hides BRAM read latency while
     * maintaining synchronous operation and gated state updates.
     *==============================================================*/
    reg  signed [WIDTH-1:0] p1_delayed;
    reg  signed [WIDTH-1:0] p2_delayed;
    reg  signed [WIDTH-1:0] p3_input;
    reg  signed [WIDTH-1:0] p3_delayed;
    reg  signed [WIDTH-1:0] p4_output;

    /*==============================================================
     * Main Sequential Logic (4-Stage Pipeline)
     *
     * STAGE 1:
     *   - Read delayed sample from circular buffer at read_ptr
     *
     * STAGE 2:
     *   - Propagate delayed sample through pipeline
     *
     * STAGE 3:
     *   - Latch the dry (input) sample for alignment
     *   - Continue propagating delayed sample
     *
     * STAGE 4:
     *   - Compute mixed output: (dry * (256-mix) + wet * mix) / 256
     *   - Write back to delay line: input + (delayed * feedback) / 256
     *   - Increment circular buffer pointer
     *
     * All updates occur only when handshake is true: i_tvalid && o_tready
     *==============================================================*/
    always @(posedge tclk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset: clear all pipeline registers and pointer
            write_ptr  <= 0;
            p1_delayed <= 0;
            p2_delayed <= 0;
            p3_input   <= 0;
            p3_delayed <= 0;
            p4_output  <= 0;
        end
        else if (i_tvalid && o_tready) begin
            // Stage 1: Read from delay line
            p1_delayed <= delay_mem[read_ptr];

            // Stage 2: Propagate delayed sample
            p2_delayed <= p1_delayed;

            // Stage 3: Latch dry input and propagate delayed
            p3_input   <= $signed(i_tdata);
            p3_delayed <= p2_delayed;

            // Stage 4: Mix and write
            p4_output <= do_mix(p3_input, p3_delayed, mix);
            delay_mem[write_ptr] <= do_write(p3_input, p3_delayed, feedback);

            // Increment write pointer with wraparound
            write_ptr <= (write_ptr == (MAX_DELAY_SAMPLES - 1)) ?
                         {ADDR_WIDTH{1'b0}} :
                         (write_ptr + 1'b1);
        end
    end

    /*==============================================================
     * Mix Function: Linear blend between dry and wet
     *
     * Formula: output = (dry * (256 - mix) + wet * mix) / 256
     *
     * Parameters:
     *   dry  : Dry signal (direct input)
     *   wet  : Wet signal (delayed sample)
     *   m    : Mix coefficient (0-255)
     *     m=0   : fully dry (output = dry)
     *     m=128 : 50/50 blend
     *     m=255 : fully wet (output = wet)
     *
     * Output is saturated to 24-bit signed range [-2^23, 2^23-1]
     * to prevent overflow in fixed-point arithmetic.
     *==============================================================*/
    function signed [WIDTH-1:0] do_mix;
        input signed [WIDTH-1:0] dry;
        input signed [WIDTH-1:0] wet;
        input [7:0]              m;
        reg signed [31:0]        acc;
        reg [23:0]               result;
    begin
        // Compute weighted sum
        acc = (dry * (256 - m)) + (wet * m);
        
        // Divide by 256 via right shift
        acc = acc >>> 8;

        // Saturate to 24-bit signed range
        if (acc > 32'h007FFFFF) begin
            result = 24'h7FFFFF;  // Positive overflow
        end
        else if (acc[31] && (acc[30:23] != 8'hFF)) begin
            result = 24'h800000;  // Negative overflow
        end
        else begin
            result = acc[23:0];   // No overflow
        end
        
        do_mix = result;
    end
    endfunction

    /*==============================================================
     * Write Function: Input + Feedback term
     *
     * Formula: write_sample = input + (delayed * feedback) / 256
     *
     * Parameters:
     *   inp     : Dry input signal
     *   delayed : Delayed sample from buffer
     *   fb      : Feedback coefficient (0-255)
     *     fb=0   : single-repeat echo (no feedback)
     *     fb=64  : ~1/4 amplitude feedback
     *     fb=128 : ~1/2 amplitude feedback (risky, may oscillate)
     *     fb=255 : maximum feedback (near oscillation)
     *
     * The scaled delayed sample is mixed with the input before
     * writing back into the delay line. This creates cascading
     * repeats that decay over time (or sustain if fb is high).
     *
     * Output is saturated to prevent feedback windup and clipping.
     *==============================================================*/
    function signed [WIDTH-1:0] do_write;
        input signed [WIDTH-1:0] inp;
        input signed [WIDTH-1:0] delayed;
        input [7:0]              fb;
        reg signed [31:0]        acc;
        reg [23:0]               result;
    begin
        // Compute feedback term and add to input
        acc = inp + ((delayed * fb) >>> 8);

        // Saturate to 24-bit signed range
        if (acc > 32'h007FFFFF) begin
            result = 24'h7FFFFF;
        end
        else if (acc[31] && (acc[30:23] != 8'hFF)) begin
            result = 24'h800000;
        end
        else begin
            result = acc[23:0];
        end
        
        do_write = result;
    end
    endfunction

    /*==============================================================
     * Output Assignment
     *
     * Connect the final pipeline register directly to the output.
     * o_tvalid and o_tdata both respect the AXI handshake condition.
     *==============================================================*/
    assign o_tdata = p4_output;

    /*==============================================================
     * Initialization: Clear delay memory
     *==============================================================*/
    integer i;
    initial begin
        for (i = 0; i < MAX_DELAY_SAMPLES; i = i + 1)
            delay_mem[i] = {WIDTH{1'b0}};
    end

endmodule

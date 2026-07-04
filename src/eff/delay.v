`timescale 1ns / 1ps

/*==============================================================
 * DELAY EFFECT MODULE (Corrected)
 *
 * A mono delay/echo effect for FPGA guitar pedal platform.
 * * Features:
 * - Circular buffer delay line (configurable, up to 96k samples)
 * - Variable delay time in samples
 * - Wet/dry mix parameter (0=dry, 255=wet)
 * - Feedback loop for repeating echoes
 * - AXI-Stream handshake with pipeline valid tracking
 * - 4-stage pipeline aligning dry/wet signals seamlessly
 *
 * Parameters:
 * WIDTH             : Sample bit-width (default 24)
 * MAX_DELAY_SAMPLES : Delay buffer size in samples (default 96000)
 * ADDR_WIDTH        : Address bits for delay buffer (default 17)
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
    input  wire [ADDR_WIDTH-1:0] delay_samples,  
    input  wire [7:0]            mix,            
    input  wire [7:0]            feedback        
);

    /*==============================================================
     * AXI-Stream Handshake
     *
     * i_tready accepts data whenever the downstream is ready.
     * o_tvalid is driven by the valid bit emerging from Stage 4.
     *==============================================================*/
    reg v1, v2, v3, v4;
    assign i_tready = o_tready;
    assign o_tvalid = v4;

    /*==============================================================
     * Delay Line Memory (Circular Buffer)
     *==============================================================*/
    reg signed [WIDTH-1:0] delay_mem [0:MAX_DELAY_SAMPLES-1];
    reg [ADDR_WIDTH-1:0]   write_ptr;

    /*==============================================================
     * Read Pointer Calculation (Combinational)
     *==============================================================*/
    wire [ADDR_WIDTH-1:0] read_ptr;
    assign read_ptr = (write_ptr >= delay_samples) ?
                      (write_ptr - delay_samples) :
                      (write_ptr + MAX_DELAY_SAMPLES - delay_samples);

    /*==============================================================
     * Pipeline Stages (Aligned Data Path)
     *==============================================================*/
    reg signed [WIDTH-1:0] p1_input,     p2_input,     p3_input;
    reg signed [WIDTH-1:0] p1_delayed,   p2_delayed,   p3_delayed;
    reg [ADDR_WIDTH-1:0]   p1_write_ptr, p2_write_ptr, p3_write_ptr;
    reg signed [WIDTH-1:0] p4_output;

    /*==============================================================
     * Main Sequential Logic (4-Stage Synchronous Pipeline)
     *
     * Data and valid flags shift through the pipeline ONLY when 
     * the downstream master is ready (o_tready).
     *==============================================================*/
    always @(posedge tclk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= 0;
            v1 <= 0; v2 <= 0; v3 <= 0; v4 <= 0;
            p4_output <= 0;
        end
        else if (o_tready) begin
            
            // STAGE 1: BRAM Read & Input Capture
            v1 <= i_tvalid;
            if (i_tvalid) begin
                // Synchronous BRAM read maps exactly to this construct
                p1_delayed   <= delay_mem[read_ptr];
                p1_input     <= $signed(i_tdata);
                p1_write_ptr <= write_ptr;

                // Advance write pointer for the next incoming sample
                write_ptr <= (write_ptr == (MAX_DELAY_SAMPLES - 1)) ?
                             {ADDR_WIDTH{1'b0}} : (write_ptr + 1'b1);
            end

            // STAGE 2: Propagate
            v2 <= v1;
            if (v1) begin
                p2_delayed   <= p1_delayed;
                p2_input     <= p1_input;
                p2_write_ptr <= p1_write_ptr;
            end

            // STAGE 3: Propagate (Data is now fully aligned)
            v3 <= v2;
            if (v2) begin
                p3_delayed   <= p2_delayed;
                p3_input     <= p2_input;
                p3_write_ptr <= p2_write_ptr;
            end

            // STAGE 4: Mix & Writeback
            v4 <= v3;
            if (v3) begin
                p4_output <= do_mix(p3_input, p3_delayed, mix);
                
                // Write back into the exact slot that was allocated in Stage 1
                delay_mem[p3_write_ptr] <= do_write(p3_input, p3_delayed, feedback);
            end
        end
    end

    /*==============================================================
     * Output Assignment
     *==============================================================*/
    assign o_tdata = p4_output;

    /*==============================================================
     * Math Functions (Parameter-Safe & Properly Signed)
     *==============================================================*/
    function signed [WIDTH-1:0] do_mix;
        input signed [WIDTH-1:0] dry;
        input signed [WIDTH-1:0] wet;
        input [7:0]              m;
        
        reg signed [47:0] acc;
        reg signed [47:0] weight_dry;
        reg signed [47:0] weight_wet;
        reg signed [47:0] max_val;
        reg signed [47:0] min_val;
    begin
        // Force evaluation as signed integers to prevent zero-extension bugs
        weight_dry = $signed({1'b0, 9'd256 - {1'b0, m}});
        weight_wet = $signed({1'b0, m});
        
        // Dynamically compute saturation limits based on parameterized WIDTH
        max_val =  (1 << (WIDTH-1)) - 1;
        min_val = -(1 << (WIDTH-1));

        acc = (dry * weight_dry) + (wet * weight_wet);
        acc = acc >>> 8;

        if (acc > max_val)      do_mix = max_val[WIDTH-1:0];
        else if (acc < min_val) do_mix = min_val[WIDTH-1:0];
        else                    do_mix = acc[WIDTH-1:0];
    end
    endfunction

    function signed [WIDTH-1:0] do_write;
        input signed [WIDTH-1:0] inp;
        input signed [WIDTH-1:0] delayed;
        input [7:0]              fb;
        
        reg signed [47:0] acc;
        reg signed [47:0] fb_weight;
        reg signed [47:0] max_val;
        reg signed [47:0] min_val;
    begin
        fb_weight = $signed({1'b0, fb});
        max_val   =  (1 << (WIDTH-1)) - 1;
        min_val   = -(1 << (WIDTH-1));

        acc = $signed(inp) + ((delayed * fb_weight) >>> 8);

        if (acc > max_val)      do_write = max_val[WIDTH-1:0];
        else if (acc < min_val) do_write = min_val[WIDTH-1:0];
        else                    do_write = acc[WIDTH-1:0];
    end
    endfunction

    /*==============================================================
     * Initialization: Clear delay memory for synthesis
     *==============================================================*/
    integer i;
    initial begin
        for (i = 0; i < MAX_DELAY_SAMPLES; i = i + 1)
            delay_mem[i] = {WIDTH{1'b0}};
    end

endmodule
`timescale 1ns / 1ps

module transceiver_feeder #(
    parameter SCK_HALF_PERIOD = 163,   
                                        
                                        
    parameter NUM_SAMPLES     = 0,      
                                        
                                        
    parameter SAMPLE_MAX      = 48000   
                                        
)(
    input  wire         clk,       // system clock (un-used now)
    input  wire         rst_n,     // active-low async reset

    output reg          done,      // asserted when all samples exhausted

    output reg          sck,       // bit clock
    output reg          ws,        // word select (L/R)
    output reg          sd         // serial data
);

    // Storage
    reg signed [23:0]   sample_mem [0:SAMPLE_MAX-1];  

    // Free-running SCK clock generator
    initial begin
        sck = 1'b0;
        forever begin
            #SCK_HALF_PERIOD sck = ~sck;
        end
    end

    // Sequential Main Controller
    initial begin : SEQ
        integer s, b, z;
        integer sample_count; // Fixes the loop overwriting bug

        // Default states during reset
        ws   = 1'b0;
        sd   = 1'b0;
        done = 1'b0;

        // Wait cleanly for reset de-assertion, then sync to SCK
        @(posedge rst_n);
        @(posedge sck);             
        @(posedge sck);             

        // Load files
        $readmemh("samples.hex", sample_mem);

        // Determine exact boundaries cleanly
        if (NUM_SAMPLES > 0) begin
            sample_count = NUM_SAMPLES;
        end else begin
            sample_count = SAMPLE_MAX;
            for (b = 0; b < SAMPLE_MAX; b = b + 1) begin
                if (sample_mem[b] === 24'b0) begin
                    sample_count = b;
                    b = SAMPLE_MAX;  // break
                end
            end
        end

        // Setup initial frame state 
        ws = 1'b1;

        for (s = 0; s < sample_count; s = s + 1) begin

            // ── LEFT CHANNEL (ws -> 0) ──────────────────────────────────────
            @(negedge sck);
            ws = 1'b0;
            sd = sample_mem[s][23];

            for (b = 22; b >= 0; b = b - 1) begin
                @(negedge sck);
                sd = sample_mem[s][b];
            end

            for (z = 0; z < 8; z = z + 1) begin
                @(negedge sck);
                sd = 1'b0;
            end

            // ── RIGHT CHANNEL (ws -> 1) ─────────────────────────────────────
            @(negedge sck);
            ws = 1'b1;
            sd = sample_mem[s][23];

            for (b = 22; b >= 0; b = b - 1) begin
                @(negedge sck);
                sd = sample_mem[s][b];
            end

            for (z = 0; z < 8; z = z + 1) begin
                @(negedge sck);
                sd = 1'b0;
            end
        end

        // All samples completed
        done = 1'b1;

        // Zeroes stream loop
        forever begin
            @(negedge sck);
            ws = 1'b0;
            sd = 1'b0;

            for (b = 0; b < 31; b = b + 1) begin
                @(negedge sck);
                sd = 1'b0;
            end

            @(negedge sck);
            ws = 1'b1;
            sd = 1'b0;

            for (b = 0; b < 31; b = b + 1) begin
                @(negedge sck);
                sd = 1'b0;
            end
        end
    end

endmodule
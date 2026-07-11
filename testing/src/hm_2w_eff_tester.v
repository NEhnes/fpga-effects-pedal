`timescale 1ns / 1ps
`include "../../src/eff/hm_2w.v"

/*
 * HM-2W EFFECT TESTER
 *
 * Reads 24-bit signed hex values from input.hex, runs them through the
 * HM-2W Boss metal distortion DSP effect, and writes the processed
 * output to hm-2w-output.hex.
 *
 * The HM-2W implements a multi-stage pipeline:
 *   1. Distortion pre-gain
 *   2. Soft-clip LUT (piecewise-linear)
 *   3. Asymmetric hard-clip (Ge diode)
 *   4. Biquad Low EQ (@87Hz)
 *   5. Biquad High EQ (@1kHz)
 *   6. Makeup gain
 *
 * Pipeline depth is ~5-6 cycles due to cascaded biquad processing.
 *
 * Usage:
 *   1. Place input.hex in the sim directory (one 24-bit hex value per line)
 *   2. Run simulation: bash hm-2w-test.sh
 *   3. Find processed output in ../data/hex/hm-2w-output.hex
 *   4. WAV conversion and waveform overlay are automatic
 *
 * To adapt parameters:
 *   - Modify the DIST, COLOR_MIX_L, COLOR_MIX_H, LEVEL, MODE_SELECT
 *     values in the "Configure effect parameters" section below
 *   - Recompile and run
 *
 */

module hm_2w_eff_tester();

    //==========================================================
    // CONFIGURABLE PARAMETERS
    //==========================================================
    parameter PIPELINE_DEPTH = 6;  // Cascaded distortion + dual biquads + makeup


    //==========================================================
    // CLOCK AND RESET
    //==========================================================
    reg clk;
    reg rst_n;


    //==========================================================
    // DUT SIGNALS (AXI-STREAM)
    //==========================================================
    reg  signed [23:0] i_tdata;
    reg                i_tvalid;
    wire               i_tready;

    reg                o_tready;
    wire               o_tvalid;
    wire signed [23:0] o_tdata;


    //==========================================================
    // EFFECT PARAMETERS
    //==========================================================
    // All parameters are 16-bit fixed-point (Q2.14 format unless noted)
    // Unity gain = 0x4000 (1.0×)
    
    reg [15:0] dist;          // Distortion pre-gain (0x4000 = unity 1.0×)
    reg [15:0] color_mix_l;   // Low EQ gain @87Hz (0x4000 = no EQ)
    reg [15:0] color_mix_h;   // High EQ gain @1kHz (0x4000 = no EQ)
    reg [15:0] level;         // Makeup gain (0x4000 = unity, no makeup)
    reg        mode_select;    // 0=Standard HM-2 curve, 1=Custom (higher Q)


    //==========================================================
    // FILE I/O
    //==========================================================
    integer fd_in;
    integer fd_out;
    integer scan_result;
    reg  [23:0] hex_val;


    //==========================================================
    // MEMORY FOR SAMPLES
    //==========================================================
    reg signed [23:0] sample_mem [0:16777215];


    //==========================================================
    // TEST CONTROL
    //==========================================================
    integer i;
    integer num_samples;
    integer sample_count;
    integer line_count;


    //==========================================================
    // DUT INSTANTIATION
    //==========================================================
    hm_2w #(
        .WIDTH(24)
    ) dut (
        // === Control Parameters ===
        .dist(dist),
        .color_mix_l(color_mix_l),
        .color_mix_h(color_mix_h),
        .level(level),
        .mode_select(mode_select),

        // === System Interface ===
        .tclk(clk),
        .rst_n(rst_n),

        // === AXI-Stream Input ===
        .i_tdata(i_tdata),
        .i_tvalid(i_tvalid),
        .i_tready(i_tready),

        // === AXI-Stream Output ===
        .o_tready(o_tready),
        .o_tvalid(o_tvalid),
        .o_tdata(o_tdata)
    );


    //==========================================================
    // CLOCK GENERATION
    //==========================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;  // 10ns period (100 MHz)
    end


    //==========================================================
    // WAVEFORM DUMP
    //==========================================================
    initial begin
        $dumpfile("hm_2w_eff_tester.vcd");
        $dumpvars(0, hm_2w_eff_tester);
    end


    //==========================================================
    // MAIN TEST SEQUENCE
    //==========================================================
    initial begin

        //---- Reset ----
        rst_n = 1'b0;
        i_tdata   = 24'h000000;
        i_tvalid  = 1'b0;
        o_tready  = 1'b0;
        dist      = 16'h4000;  // Safe: unity gain
        color_mix_l = 16'h4000;  // Safe: no EQ
        color_mix_h = 16'h4000;  // Safe: no EQ
        level     = 16'h4000;  // Safe: no makeup
        mode_select = 1'b0;    // Standard mode
        #50;
        rst_n = 1'b1;
        #20;

        //---- Configure effect parameters for classic HM-2W metal tone ----
        // These values produce the classic Boss HM-2W "wall of metal" character:
        // - High distortion with soft+hard clipping for organic breakup
        // - Boosted low end for bass punch (@87Hz)
        // - Scooped mids, pushed highs for aggression (@1kHz)
        // - Makeup gain to compensate for EQ losses
        
        dist         = 16'h7800;  // ~1.875× distortion pre-gain (aggressive saturation)
        color_mix_l  = 16'h5000;  // +1.25× gain on low EQ (bass punch)
        color_mix_h  = 16'h3000;  // −1.25× attenuation on high EQ (dark, scooped)
        level        = 16'h5800;  // ~1.375× makeup gain (recover EQ losses)
        mode_select  = 1'b0;      // Standard HM-2 EQ curve

        //---- Open files ----
        fd_in = $fopen("../data/input.hex", "r");
        if (fd_in == 0) begin
            $display("[ERROR] Could not open input.hex");
            $display("        Place your 24-bit hex samples in ../data/input.hex (one per line)");
            $finish;
        end

        fd_out = $fopen("../data/hex/hm-2w-output.hex", "w");
        if (fd_out == 0) begin
            $display("[ERROR] Could not open hm-2w-output.hex for writing");
            $finish;
        end

        //---- Print configuration ----
        $display("========================================");
        $display("  HM-2W METAL DISTORTION EFFECT TESTER");
        $display("========================================");
        $display("  Module:          hm_2w");
        $display("  Pipeline:        %0d cycles", PIPELINE_DEPTH);
        $display("  Input:           ../data/input.hex");
        $display("  Output:          ../data/hex/hm-2w-output.hex");
        $display("");
        $display("  PARAMETER CONFIGURATION:");
        $display("    DIST (pre-gain)    = 0x%04h  (~1.88× saturation boost)", dist);
        $display("    COLOR_MIX_L (@87Hz) = 0x%04h  (+1.25× bass punch)", color_mix_l);
        $display("    COLOR_MIX_H (@1kHz) = 0x%04h  (−1.25× high scoop)", color_mix_h);
        $display("    LEVEL (makeup)     = 0x%04h  (+1.38× recovery)", level);
        $display("    MODE               = %s", mode_select ? "Custom (higher Q)" : "Standard (original HM-2)");
        $display("");
        $display("  EFFECT STAGES:");
        $display("    1. Distortion Pre-Gain");
        $display("    2. Piecewise-Linear Soft-Clip LUT");
        $display("    3. Asymmetric Hard-Clip (Ge Diode)");
        $display("    4. Biquad Low EQ @87Hz (gyrator simulation)");
        $display("    5. Biquad High EQ @1kHz (gyrator simulation)");
        $display("    6. Makeup Gain / Volume Control");
        $display("========================================");


        //---- Phase 0: Read all samples into memory ----
        num_samples = 0;
        while (!$feof(fd_in)) begin
            scan_result = $fscanf(fd_in, "%h\n", hex_val);
            if (scan_result == 1) begin
                sample_mem[num_samples] = hex_val;
                num_samples = num_samples + 1;
            end
        end
        $fclose(fd_in);
        $display("  Read %0d samples from input.hex", num_samples);
        $display("");

        if (num_samples == 0) begin
            $display("[ERROR] No valid hex samples found in input.hex");
            $fclose(fd_out);
            $finish;
        end


        //---- Phase 1: Feed first PIPELINE_DEPTH samples (no captures yet) ----
        // Prime the pipeline with initial samples before capturing output
        if (num_samples > 0) begin
            @(posedge clk) begin
                i_tdata  = sample_mem[0];
                i_tvalid = 1'b1;
                o_tready = 1'b1;
            end
        end

        for (i = 1; i < PIPELINE_DEPTH && i < num_samples; i = i + 1) begin
            @(posedge clk) begin
                i_tdata = sample_mem[i];
            end
        end


        //---- Phase 2: Interleave capture + feed (full throughput) ----
        // From sample PIPELINE_DEPTH onwards, capture one output per cycle
        // while simultaneously feeding the next input
        sample_count = 0;

        for (i = PIPELINE_DEPTH; i < num_samples; i = i + 1) begin
            @(posedge clk) begin
                $fwrite(fd_out, "%06h\n", o_tdata);
                sample_count = sample_count + 1;
                i_tdata = sample_mem[i];
            end
        end


        //---- Phase 3: Drain remaining pipeline samples ----
        // After all inputs are fed, capture the final PIPELINE_DEPTH outputs
        // Keep i_tvalid HIGH during drain so state registers keep updating
        for (i = 0; i < PIPELINE_DEPTH; i = i + 1) begin
            @(posedge clk) begin
                $fwrite(fd_out, "%06h\n", o_tdata);
                sample_count = sample_count + 1;
            end
        end

        // Now kill the valid signal after pipeline is drained
        i_tvalid = 1'b0;


        //---- Done ----
        $fclose(fd_out);

        $display("========================================");
        $display("  PROCESSING COMPLETE");
        $display("========================================");
        $display("  Wrote %0d samples to hm-2w-output.hex", sample_count);
        $display("  Expected samples: %0d", num_samples + PIPELINE_DEPTH);
        $display("");

        #50;
        $finish;
    end

endmodule

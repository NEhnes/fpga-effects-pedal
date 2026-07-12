`timescale 1ns / 1ps
`include "../../src/eff/hm_2w.v"

/*
 * HM-2W METAL DISTORTION EFFECT TESTER (STREAMING VERSION)
 *
 * MAJOR CHANGES FROM ORIGINAL:
 * 1. Streams input from disk line-by-line (no pre-loading)
 * 2. Disabled VCD dumping (use only for small test cases)
 * 3. Simplified clock generation (free-running, stops on $finish)
 * 4. Progress reporting every 10k samples (helps diagnose hangs)
 *
 * This version should handle 750k+ samples without hanging.
 */
module hm_2w_eff_tester();

    parameter PIPELINE_DEPTH = 1;

    // ======= CLOCK AND RESET =======
    reg clk;
    reg rst_n;

    // ======= DUT SIGNALS (AXI-STREAM) =======
    reg  signed [23:0] i_tdata;
    reg                i_tvalid;
    wire               i_tready;

    reg                o_tready;
    wire               o_tvalid;
    wire signed [23:0] o_tdata;

    // ======= EFFECT PARAMETERS =======
    reg [15:0] dist;
    reg [15:0] color_mix_l;
    reg [15:0] color_mix_h;
    reg [15:0] level;
    reg        mode_select;

    // ======= FILE I/O =======
    integer fd_in;
    integer fd_out;
    integer scan_result;
    reg  [23:0] hex_val;

    // ======= TEST CONTROL =======
    integer i;
    integer num_samples;
    integer sample_count;

    // ======= DUT INSTANTIATION =======
    hm_2w #(
        .WIDTH(24)
    ) dut (
        .tclk(clk),
        .rst_n(rst_n),
        .i_tdata(i_tdata),
        .i_tvalid(i_tvalid),
        .i_tready(i_tready),
        .o_tready(o_tready),
        .o_tvalid(o_tvalid),
        .o_tdata(o_tdata),
        .dist(dist),
        .color_mix_l(color_mix_l),
        .color_mix_h(color_mix_h),
        .level(level),
        .mode_select(mode_select)
    );

    // ======= CLOCK GENERATION (Simple, Free-Running) =======
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ======= MAIN TEST SEQUENCE =======
    initial begin

        // ---- Reset ----
        rst_n = 1'b0;
        i_tdata   = 24'h000000;
        i_tvalid  = 1'b0;
        o_tready  = 1'b0;
        dist      = 16'h4000;
        color_mix_l = 16'h4000;
        color_mix_h = 16'h4000;
        level     = 16'h4000;
        mode_select = 1'b0;
        #50;
        rst_n = 1'b1;
        #20;


	/*
	================= COMMON PRESETS ================
	Subtle Meta (Rhythm)
	dist: 0x4800, color_mix_l: 0x3000, color_mix_h: 0x3500, level: 0x4000, mode: 0

	Classic HM-2 Chug (heavy sludge)
	dist: 0x5000, color_mix_l: 0x4000, color_mix_h: 0x4000, level: 0x4800, mode: 0

	Aggressive Lead (cutting presence)
	dist: 0x5400, color_mix_l: 0x2500, color_mix_h: 0x4800, level: 0x5000, mode: 1

	Extreme Filth (custom mode maxed)
	dist: 0x5800, color_mix_l: 0x4500, color_mix_h: 0x5000, level: 0x5200, mode: 1
	*/

        // ---- Configure effect parameters ----
        dist        = 16'h9999;
        color_mix_l = 16'h8000;
        color_mix_h = 16'h4000;
        level       = 16'h5400;
        mode_select = 1'b1;

        // ---- Open files ----
        fd_in = $fopen("../data/input.hex", "r");
        if (fd_in == 0) begin
            $display("[ERROR] Could not open input.hex");
            $finish;
        end

        fd_out = $fopen("../data/hex/hm_2w-output.hex", "w");
        if (fd_out == 0) begin
            $display("[ERROR] Could not open hm_2w-output.hex for writing");
            $finish;
        end

        // ---- Print configuration ----
        $display("========================================");
        $display("  HM-2W METAL DISTORTION EFFECT TESTER");
        $display("  (STREAMING INPUT VERSION)");
        $display("========================================");
        $display("  Module:          hm_2w");
        $display("  Pipeline:        %0d cycle(s)", PIPELINE_DEPTH);
        $display("========================================");
        $display("  CONTROL PARAMETERS:");
        $display("    DIST        = 0x%04h", dist);
        $display("    COLOR_MIX_L = 0x%04h", color_mix_l);
        $display("    COLOR_MIX_H = 0x%04h", color_mix_h);
        $display("    LEVEL       = 0x%04h", level);
        $display("    MODE        = %0d", mode_select);
        $display("========================================");
        $display("  Processing samples...");

        // ---- Phase: Streaming input (read line-by-line, no pre-load) ----
        num_samples = 0;
        sample_count = 0;
        i_tvalid = 1'b1;
        o_tready = 1'b1;

        // Read first sample
        scan_result = $fscanf(fd_in, "%h\n", hex_val);
        if (scan_result != 1) begin
            $display("[ERROR] Could not read first sample from input.hex");
            $fclose(fd_in);
            $fclose(fd_out);
            $finish;
        end

        i_tdata = hex_val;
        num_samples = 1;

        // ---- Main loop: stream input, capture output ----
        forever begin
            @(posedge clk) begin
                // Capture output from previous sample
                if (num_samples > 1) begin
                    $fwrite(fd_out, "%06h\n", o_tdata);
                    sample_count = sample_count + 1;
                    
                    // Progress reporting every 10k samples
                    if (sample_count % 10000 == 0) begin
                        $display("  ✓ Processed %0d samples...", sample_count);
                    end
                end
                
                // Try to read next sample
                scan_result = $fscanf(fd_in, "%h\n", hex_val);
                
                if (scan_result == 1) begin
                    // Valid sample read
                    i_tdata = hex_val;
                    num_samples = num_samples + 1;
                end else begin
                    // EOF reached
                    i_tvalid = 1'b0;
                    
                    // Capture the very last output
                    @(posedge clk) begin
                        $fwrite(fd_out, "%06h\n", o_tdata);
                        sample_count = sample_count + 1;
                    end
                    
                    // Done
                    $fclose(fd_in);
                    $fclose(fd_out);
                    
                    $display("");
                    $display("========================================");
                    $display("  PROCESSING COMPLETE ✓");
                    $display("========================================");
                    $display("  Total input samples:  %0d", num_samples);
                    $display("  Total output samples: %0d", sample_count);
                    $display("  Output file: ../data/hex/hm_2w-output.hex");
                    $display("========================================");
                    
                    #50;
                    $finish;
                end
            end
        end

    end

endmodule

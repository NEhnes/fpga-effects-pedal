`timescale 1ns / 1ps
`include "../../src/eff/delay.v"

/*
 * DELAY EFFECT TESTER (CORRECTED)
 *
 * Reads 24-bit signed hex values from input.hex, runs them through the
 * delay DSP effect, and writes the processed output to output.hex.
 *
 * INTERFACE FIXED:
 *   - Changed mix/feedback to use 0-255 range (not Q1.14)
 *   - Removed non-existent Q-format parameters
 *   - Updated DUT instantiation to match actual delay module ports
 *
 * Usage:
 *   1. Place input.hex in the sim directory (one 24-bit hex value per line)
 *   2. Run simulation
 *   3. Find processed output in output.hex
 *
 * To adapt for a different effect:
 *   - Change the `include path
 *   - Replace the DUT instantiation
 *   - Update effect parameter registers and assignments
 */
module delay_eff_tester();

  // ======= CONFIGURABLE PARAMETERS =======
  parameter PIPELINE_DEPTH = 4;  // Delay has 4-stage pipeline
  parameter DEPTH = 131072;        // Must be power of 2

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
  reg [16:0] delay_samples;      // Integer: 1 to DEPTH (17-bit for ADDR_WIDTH)
  reg [7:0]  feedback;           // 0-255 (0=no feedback, 255=maximum)
  reg [7:0]  mix;                // 0-255 (0=dry, 128=50%, 255=wet)

  // ======= FILE I/O =======
  integer fd_in;
  integer fd_out;
  integer scan_result;
  reg  [23:0] hex_val;

  // ======= MEMORY FOR SAMPLES =======
  reg signed [23:0] sample_mem [0:16777215];

  // ======= TEST CONTROL =======
  integer i;
  integer num_samples;
  integer sample_count;
  integer line_count;

  // ======= DUT INSTANTIATION =======
  delay #(
      .WIDTH(24),
      .MAX_DELAY_SAMPLES(DEPTH),
      .ADDR_WIDTH(17)
  ) dut (
      .tclk(clk),
      .rst_n(rst_n),
      .i_tdata(i_tdata),
      .i_tvalid(i_tvalid),
      .i_tready(i_tready),
      .o_tready(o_tready),
      .o_tvalid(o_tvalid),
      .o_tdata(o_tdata),
      .delay_samples(delay_samples),
      .mix(mix),
      .feedback(feedback)
  );

  // ======= CLOCK GENERATION =======
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;  // 10ns period (100 MHz)
  end

  // ======= WAVEFORM DUMP =======
  initial begin
    $dumpfile("delay_eff_tester.vcd");
    $dumpvars(0, delay_eff_tester);
  end

  // ======= MAIN TEST SEQUENCE =======
  initial begin

    // ---- Reset ----
    rst_n = 1'b0;
    i_tdata        = 24'h000000;
    i_tvalid       = 1'b0;
    o_tready       = 1'b1;
    delay_samples  = 17'd512;     // 512-sample delay (half buffer)
    feedback       = 8'd128;      // 50% feedback (0-255 range)
    mix            = 8'd128;      // 50% wet/dry mix
    #50;
    rst_n = 1'b1;
    #20;

    // ---- Configure effect with MODERATE DELAY PARAMETERS ----
    // SPACIOUS DELAY: Medium delay time + controlled feedback + balanced mix
    delay_samples  = 17'd10000;     // --time--
    feedback       = 8'd96;       // 37.5% feedback (0x60 ~= 96/255)
    mix            = 8'd49;       // ~20% wet signal

    // ---- Open files ----
    fd_in = $fopen("../data/input.hex", "r");
    if (fd_in == 0) begin
      $display("[ERROR] Could not open input.hex");
      $display("        Place your 24-bit hex samples in input.hex (one per line)");
      $finish;
    end

    fd_out = $fopen("../data/hex/delay-output.hex", "w");
    if (fd_out == 0) begin
      $display("[ERROR] Could not open delay-output.hex for writing");
      $finish;
    end

    // ---- Print configuration ----
    $display("========================================");
    $display("  DELAY EFFECT TESTER");
    $display("========================================");
    $display("  Module:          delay");
    $display("  Buffer Depth:    %0d samples", DEPTH);
    $display("  delay_samples:   %0d (17-bit address)", delay_samples);
    $display("  feedback:        %0d/255 (0-255 range)", feedback);
    $display("  mix:             %0d/255 (0=dry, 128=50%%, 255=wet)", mix);
    $display("  Pipeline:        %0d cycles", PIPELINE_DEPTH);
    $display("  Input:           input.hex");
    $display("  Output:          delay-output.hex");
    $display("========================================");

    // ---- Phase 0: Read all samples into memory ----
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

    if (num_samples == 0) begin
      $display("[ERROR] No valid hex samples found in input.hex");
      $fclose(fd_out);
      $finish;
    end

    // ---- Phase 1: Feed first sample ----
    // Delay has 4-stage pipeline, so outputs appear after 4 cycles.
    if (num_samples > 0) begin
      @(posedge clk) begin
        i_tdata  = sample_mem[0];
        i_tvalid = 1'b1;
        o_tready = 1'b1;
      end
    end

    // ---- Phase 2: Full throughput (1 sample/cycle) ----
    // Account for 4-cycle pipeline latency before capturing outputs
    sample_count = 0;

    for (i = 1; i < num_samples; i = i + 1) begin
      @(posedge clk) begin
        i_tdata = sample_mem[i];
        // Only write output after pipeline has filled (after sample 4)
        if (i >= PIPELINE_DEPTH) begin
          $fwrite(fd_out, "%06h\n", o_tdata);
          sample_count = sample_count + 1;
        end
      end
    end

    // ---- Phase 3: Capture remaining pipeline outputs ----
    // Drain the 4-stage pipeline after last input
    for (i = 0; i < PIPELINE_DEPTH; i = i + 1) begin
      @(posedge clk) begin
        i_tvalid = 1'b0;  // Stop feeding new data
        $fwrite(fd_out, "%06h\n", o_tdata);
        sample_count = sample_count + 1;
      end
    end

    // ---- Done ----
    $fclose(fd_out);

    $display("  Wrote %0d samples to delay-output.hex", sample_count);
    $display("");
    $display("========================================");
    $display("  PROCESSING COMPLETE");
    $display("========================================");

    #50;
    $finish;
  end

endmodule
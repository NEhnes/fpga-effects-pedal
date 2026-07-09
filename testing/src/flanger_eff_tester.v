`timescale 1ns / 1ps
`include "../../src/eff/flanger.v"

/*
 * FLANGER EFFECT TESTER
 *
 * Reads 16-bit signed hex values from input.hex, runs them through the
 * flanger DSP effect (variable-delay with LFO modulation), and writes
 * the processed output to output.hex.
 *
 * PIPELINE TIMING:
 *   Input is fed on cycle N.
 *   Output from that input appears on cycle N+1 (1-cycle delay).
 *   This testbench accounts for the pipeline depth by reading audio_out
 *   at the START of each cycle (before feeding the next input).
 *
 * Usage:
 *   1. Place input.hex in the data directory (one 16-bit hex value per line)
 *   2. Run simulation
 *   3. Find processed output in data/hex/flanger-output.hex
 *
 * Flanger Parameters:
 *   - depth:       Controls max delay offset (modulation depth, samples)
 *   - feedback:    Feedback coefficient (0-32767 in Q15 format)
 *   - lfo_freq:    LFO oscillation frequency control
 *   - MAX_DELAY:   Size of delay line buffer (samples)
 */
module flanger_eff_tester();

  // ======= CONFIGURABLE PARAMETERS =======
  parameter PIPELINE_DEPTH = 1;           // Flanger updates output register each cycle
  parameter MAX_DELAY = 4096;             // Delay line size
  parameter DATA_WIDTH = 24;

  // ======= CLOCK AND RESET =======
  reg clk;
  reg reset_n;

  // ======= DUT SIGNALS =======
  reg  signed [DATA_WIDTH-1:0] audio_in;
  wire signed [DATA_WIDTH-1:0] audio_out;

  // ======= EFFECT PARAMETERS =======
  reg [DATA_WIDTH-1:0] depth;             // Max delay offset (samples)
  reg [DATA_WIDTH-1:0] feedback;          // Feedback coefficient (Q15)
  reg [DATA_WIDTH-1:0] lfo_freq;          // LFO frequency control

  // ======= FILE I/O =======
  integer fd_in;
  integer fd_out;
  integer scan_result;
  reg [DATA_WIDTH-1:0] hex_val;

  // ======= MEMORY FOR SAMPLES =======
  reg signed [DATA_WIDTH-1:0] sample_mem [0:65535];

  // ======= TEST CONTROL =======
  integer i;
  integer num_samples;
  integer sample_count;

  // ======= DUT INSTANTIATION =======
  flanger #(
      .MAX_DELAY(MAX_DELAY),
      .DATA_WIDTH(DATA_WIDTH)
  ) dut (
      .clk(clk),
      .reset_n(reset_n),
      .audio_in(audio_in),
      .depth(depth),
      .feedback(feedback),
      .lfo_freq(lfo_freq),
      .audio_out(audio_out)
  );

  // ======= CLOCK GENERATION =======
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;  // 10ns period (100 MHz)
  end

  // ======= WAVEFORM DUMP =======
  initial begin
    $dumpfile("flanger_eff_tester.vcd");
    $dumpvars(0, flanger_eff_tester);
  end

  // ======= MAIN TEST SEQUENCE =======
  initial begin

    // ---- Reset ----
    reset_n = 1'b0;
    audio_in  = {DATA_WIDTH{1'b0}};
    depth     = {DATA_WIDTH{1'b0}};
    feedback  = {DATA_WIDTH{1'b0}};
    lfo_freq  = {DATA_WIDTH{1'b0}};
    #50;
    reset_n = 1'b1;
    #20;

    // ---- Configure effect with subtle FLANGER parameters ----
    // Classic flanger: very short delay (<1ms), light feedback for gentle comb filtering
    depth      = 24'h000010;      // ~1.6 samples of max delay (~33us @48kHz) — subtle sweep
    feedback   = 24'h020000;      // Q23: ~0.0156 feedback — whisper of comb filtering
    lfo_freq   = 24'h000008;      // Slow LFO sweep (~0.5 Hz equivalent)

    // ---- Open files ----
    fd_in = $fopen("../data/input.hex", "r");
    if (fd_in == 0) begin
      $display("[ERROR] Could not open input.hex");
      $display("        Place your 16-bit hex samples in input.hex (one per line)");
      $finish;
    end

    fd_out = $fopen("../data/hex/flanger-output.hex", "w");
    if (fd_out == 0) begin
      $display("[ERROR] Could not open flanger-output.hex for writing");
      $finish;
    end

    // ---- Print configuration ----
    $display("========================================");
    $display("  FLANGER EFFECT TESTER");
    $display("========================================");
    $display("  Module:          flanger");
    $display("  MAX_DELAY:       %0d samples", MAX_DELAY);
    $display("  DATA_WIDTH:      %0d bits", DATA_WIDTH);
    $display("  depth:           0x%04h (%0d samples)", depth, depth);
    $display("  feedback:        0x%04h (Q15 coefficient)", feedback);
    $display("  lfo_freq:        0x%04h (LFO sweep control)", lfo_freq);
    $display("  Pipeline:        %0d cycle", PIPELINE_DEPTH);
    $display("  Input:           input.hex");
    $display("  Output:          flanger-output.hex");
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

    // ---- Phase 1: Prime the pipeline ----
    // Feed samples continuously for MAX_DELAY cycles to fill the delay line.
    // During this warmup, output will be transitioning from zero (no feedback yet).
    // After MAX_DELAY cycles, the delay line is full and effect is stable.
    $display("  Priming delay line for %0d cycles...", MAX_DELAY);
    
    for (i = 0; i < MAX_DELAY && i < num_samples; i = i + 1) begin
      @(posedge clk) audio_in = sample_mem[i];
    end
    
    // Wait a few extra cycles for the effect to stabilize
    repeat(10) @(posedge clk);
    $display("  Delay line primed. Starting output capture.");

    // ---- Phase 2: Full throughput (1 sample/cycle) ----
    // At the start of each cycle, capture the output from the previous input.
    // Then feed the next input for processing on the next cycle.
    sample_count = 0;

    for (i = MAX_DELAY; i < num_samples; i = i + 1) begin
      @(posedge clk) begin
        // Capture output from the previous input (now available)
        $fwrite(fd_out, "%06h\n", audio_out);
        sample_count = sample_count + 1;

        // Feed next input for processing on the next cycle
        audio_in = sample_mem[i];
      end
    end

    // ---- Phase 3: Capture final output ----
    // Feed silence and read out the last processed sample
    @(posedge clk) begin
      $fwrite(fd_out, "%04h\n", audio_out);
      sample_count = sample_count + 1;
      audio_in = 16'h0000;
    end

    // ---- Done ----
    $fclose(fd_out);

    $display("  Wrote %0d samples to flanger-output.hex", sample_count);
    $display("");
    $display("========================================");
    $display("  PROCESSING COMPLETE");
    $display("========================================");

    #50;
    $finish;
  end

endmodule

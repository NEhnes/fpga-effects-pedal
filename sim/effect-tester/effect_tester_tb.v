`timescale 1ns / 1ps
`include "../hard_clip/hard_clip.v"

/*
 * EFFECT TESTER
 *
 * Reads 24-bit signed hex values from input.hex, runs them through the
 * hard_clip DSP effect, and writes the processed output to output.hex.
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
module effect_tester_tb();

  // ======= CONFIGURABLE PARAMETERS =======
  parameter PIPELINE_DEPTH = 2;  // Clock cycles from valid input to output ready

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
  reg [15:0] input_gain;         // Q1.14 (unity = 0x4000)
  reg [15:0] normalized_clip;    // Q0.16 (+/- 1.0)

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
  hard_clip #(
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
      ._input_gain(input_gain),
      ._normalized_clip(normalized_clip)
  );

  // ======= CLOCK GENERATION =======
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;  // 10ns period (100 MHz)
  end

  // ======= WAVEFORM DUMP =======
  initial begin
    $dumpfile("effect_tester_tb.vcd");
    $dumpvars(0, effect_tester_tb);
  end

  // ======= MAIN TEST SEQUENCE =======
  initial begin

    // ---- Reset ----
    rst_n = 1'b0;
    i_tdata   = 24'h000000;
    i_tvalid  = 1'b0;
    o_tready  = 1'b0;
    input_gain     = 16'h4000;    // Unity gain (Q1.14)
    normalized_clip = 16'h7FFF;   // Max threshold (no clipping)
    #50;
    rst_n = 1'b1;
    #20;

    // ---- Configure effect ----
    // Typical hard clip: moderate boost + moderate clipping
    // input_gain     = 16'h6000;    // ~1.5x gain (Q1.14)
    // normalized_clip = 16'h6000;   // Moderate clip threshold (Q0.16)

    // super AGGRESSIVE clip - proof of concept
    input_gain     = 16'h8000;    // 2.0x boost
    normalized_clip = 16'h2000;   // Heavy clipping at 0.125 threshold

    // ---- Open files ----
    fd_in = $fopen("input.hex", "r");
    if (fd_in == 0) begin
      $display("[ERROR] Could not open input.hex");
      $display("        Place your 24-bit hex samples in input.hex (one per line)");
      $finish;
    end

    fd_out = $fopen("output.hex", "w");
    if (fd_out == 0) begin
      $display("[ERROR] Could not open output.hex for writing");
      $finish;
    end

    // ---- Print configuration ----
    $display("========================================");
    $display("  EFFECT TESTER");
    $display("========================================");
    $display("  Module:       hard_clip");
    $display("  input_gain:   0x%04h (Q1.14)", input_gain);
    $display("  norm_clip:    0x%04h (Q0.16)", normalized_clip);
    $display("  Pipeline:     %0d cycles", PIPELINE_DEPTH);
    $display("  Input:        input.hex");
    $display("  Output:       output.hex");
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

    // ---- Phase 1: Feed first PIPELINE_DEPTH samples (no captures yet) ----
    // Outputs aren't ready until PIPELINE_DEPTH cycles after first feed.
    // We feed samples but don't record o_tdata until the pipeline fills.
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

    // ---- Phase 2: Interleave capture + feed (full throughput) ----
    // Each cycle: capture the output that was produced PIPELINE_DEPTH cycles ago,
    // and feed the next new sample. This sustains 1 sample/cycle.
    sample_count = 0;

    for (i = PIPELINE_DEPTH; i < num_samples; i = i + 1) begin
      @(posedge clk) begin
        $fwrite(fd_out, "%06h\n", o_tdata);
        sample_count = sample_count + 1;
        i_tdata = sample_mem[i];
      end
    end

    // ---- Phase 3: Drain remaining pipeline samples ----
    // Capture the last PIPELINE_DEPTH outputs still in the pipeline.
    for (i = 0; i < PIPELINE_DEPTH; i = i + 1) begin
      @(posedge clk) begin
        $fwrite(fd_out, "%06h\n", o_tdata);
        sample_count = sample_count + 1;
        // De-assert valid after all samples are drained
        if (i == PIPELINE_DEPTH - 1) begin
          i_tvalid = 1'b0;
        end
      end
    end

    // ---- Done ----
    $fclose(fd_out);

    $display("  Wrote %0d samples to output.hex", sample_count);
    $display("");
    $display("========================================");
    $display("  PROCESSING COMPLETE");
    $display("========================================");

    #50;
    $finish;
  end

endmodule
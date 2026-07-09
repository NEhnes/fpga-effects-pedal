`timescale 1ns / 1ps
`include "../../src/eff/noise_gate.v"

/*
 * NOISE GATE EFFECT TESTER
 *
 * Reads 24-bit signed hex values from input.hex, runs them through the
 * noise_gate DSP effect, and writes the processed output to output.hex.
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
module noise_gate_eff_tester();

  // ======= CONFIGURABLE PARAMETERS =======
  parameter PIPELINE_DEPTH = 1;  // depends on number of clocked stages in effect

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
  reg [15:0] threshold;
  reg [15:0] attack;
  reg [15:0] release_len;
  reg [15:0] makeup_gain;


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
  noise_gate #(
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
      .threshold(threshold),
      .attack(attack),
      .release_len(release_len),
      .makeup_gain(makeup_gain)
  );

  // ======= CLOCK GENERATION =======
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;  // 10ns period (100 MHz)
  end

  // ======= WAVEFORM DUMP =======
  initial begin
    $dumpfile("noise_gate_eff_tester.vcd");
    $dumpvars(0, noise_gate_eff_tester);
  end

  // ======= MAIN TEST SEQUENCE =======
  initial begin

    // ---- Reset ----
    rst_n = 1'b0;
    i_tdata   = 24'h000000;
    i_tvalid  = 1'b0;
    o_tready  = 1'b0;

    threshold   = 16'h0000; // gate always open
    attack      = 16'h0000; // instant fade-in
    release_len = 16'h0000; // instant release
    makeup_gain = 16'h0000; // less than unity

    #50;
    rst_n = 1'b1;
    #20;

    // ---- Configure effect with midpoint parameters ----
    // CHECK THE EFF SRC CODE FOR CONFIG GUIDELINES
    threshold   = 16'h7777; // halfway
    attack      = 16'h1388; // halfway through usable range
    release_len = 16'h1388; // default
    makeup_gain = 16'h1000; // unity

    // ---- Open files ----
    fd_in = $fopen("../data/input.hex", "r");
    if (fd_in == 0) begin
      $display("[ERROR] Could not open input.hex");
      $display("        Place your 24-bit hex samples in input.hex (one per line)");
      $finish;
    end

    fd_out = $fopen("../data/hex/noise-gate-output.hex", "w");
    if (fd_out == 0) begin
      $display("[ERROR] Could not open noise-gate-output.hex for writing");
      $finish;
    end

    // ---- Print configuration ----
    $display("========================================");
    $display("  NOISE GATE EFFECT TESTER");
    $display("========================================");
    $display("  Module:          noise_gate");
    $display("  threshold:       0x%04h (Q1.14)", threshold);
    $display("  attack:          0x%04h (Q3.11)", attack);
    $display("  release len:     0x%04h (Q3.11)", release_len);
    $display("  makeup gain:     0x%04h (Q3.11)", makeup_gain);
    $display("  Pipeline:        %0d cycles", PIPELINE_DEPTH);
    $display("  Input:           input.hex");
    $display("  Output:          noise-gate-output.hex");
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
    // noise_gate has combinational output path, so we see results immediately.
    if (num_samples > 0) begin
      @(posedge clk) begin
        i_tdata  = sample_mem[0];
        i_tvalid = 1'b1;
        o_tready = 1'b1;
      end
    end

    // ---- Phase 2: Full throughput (1 sample/cycle, immediate capture) ----
    sample_count = 0;

    for (i = 1; i < num_samples; i = i + 1) begin
      @(posedge clk) begin
        $fwrite(fd_out, "%06h\n", o_tdata);
        sample_count = sample_count + 1;
        i_tdata = sample_mem[i];
      end
    end

    // ---- Phase 3: Capture final output ----
    @(posedge clk) begin
      $fwrite(fd_out, "%06h\n", o_tdata);
      sample_count = sample_count + 1;
      i_tvalid = 1'b0;
    end

    // ---- Done ----
    $fclose(fd_out);

    $display("  Wrote %0d samples to noise-gate-output.hex", sample_count);
    $display("");
    $display("========================================");
    $display("  PROCESSING COMPLETE");
    $display("========================================");

    #50;
    $finish;
  end

endmodule

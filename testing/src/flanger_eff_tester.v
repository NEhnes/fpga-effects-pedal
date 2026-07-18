`timescale 1ns / 1ps
`include "../../src/eff/flanger.v"

module flanger_eff_tester();
  parameter MAX_DELAY = 4096;
  parameter DATA_WIDTH = 24;
  reg clk, reset_n;
  reg signed [DATA_WIDTH-1:0] audio_in;
  wire signed [DATA_WIDTH-1:0] audio_out;
  reg [DATA_WIDTH-1:0] depth, feedback, lfo_freq;
  integer fd_in, fd_out, scan_result, i, num_samples, sample_count;
  reg [DATA_WIDTH-1:0] hex_val;
  reg signed [DATA_WIDTH-1:0] sample_mem [0:262143];

  flanger #(.MAX_DELAY(MAX_DELAY), .DATA_WIDTH(DATA_WIDTH)) dut (
    .clk(clk), .reset_n(reset_n), .audio_in(audio_in), .depth(depth), .feedback(feedback),
    .lfo_freq(lfo_freq), .audio_out(audio_out)
  );

  initial begin clk = 0; forever #5 clk = ~clk; end
  initial begin
    $dumpfile("flanger_eff_tester.vcd"); $dumpvars(0, flanger_eff_tester);
  end

  initial begin
    reset_n = 0; audio_in = 0;
    // Audible flanger settings for 48 kHz audio:
    // 256-sample sweep (~5.3 ms), ~0.5 Hz LFO, and 18.75% feedback.
    depth = 24'h000258; // 0x008000 – 0x020000 range [gemini] higher=noticeable
    feedback = 24'h005000; // 0x200000 – 0x600000 range [gemini] higher=noticeable
    lfo_freq = 24'h000800; // 0x000300 – 0x001400 range [gemini] lower=noticeable
    #50; reset_n = 1;
    fd_in = $fopen("../data/input.hex", "r");
    if (!fd_in) begin $display("[ERROR] Could not open input.hex"); $finish; end
    fd_out = $fopen("../data/hex/flanger-output.hex", "w");
    if (!fd_out) begin $display("[ERROR] Could not open output"); $finish; end
    num_samples = 0;
    while (!$feof(fd_in) && num_samples < 262144) begin
      scan_result = $fscanf(fd_in, "%h\n", hex_val);
      if (scan_result == 1) begin sample_mem[num_samples] = hex_val; num_samples = num_samples + 1; end
    end
    $fclose(fd_in);
    if (num_samples == 0) begin $fclose(fd_out); $finish; end

    audio_in = sample_mem[0]; sample_count = 0;
    for (i = 0; i < num_samples; i = i + 1) begin
      @(posedge clk); #1;
      if (i > 0) begin $fwrite(fd_out, "%06h\n", audio_out); sample_count = sample_count + 1; end
      if (i + 1 < num_samples) audio_in = sample_mem[i + 1];
    end
    @(posedge clk); #1;
    $fwrite(fd_out, "%06h\n", audio_out); sample_count = sample_count + 1;
    $fclose(fd_out);
    $display("Wrote %0d samples", sample_count);
    #50; $finish;
  end
endmodule

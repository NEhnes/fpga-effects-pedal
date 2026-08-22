`timescale 1ns / 1ps
`include "../../src/eff/chorus.v"

module chorus_eff_tester();
  parameter DATA_WIDTH = 24;
  parameter DELAY_DEPTH = 2048;
  reg clk, rst_n;
  reg signed [DATA_WIDTH-1:0] i_tdata;
  reg i_tvalid, o_tready;
  wire i_tready, o_tvalid;
  wire signed [DATA_WIDTH-1:0] o_tdata;
  reg [15:0] rate, depth, mix;
  reg signed [15:0] makeup_gain;
  integer fd_in, fd_out, scan_result, i, num_samples, sample_count;
  reg [DATA_WIDTH-1:0] hex_val;
  reg signed [DATA_WIDTH-1:0] sample_mem [0:262143];

  chorus #(.WIDTH(DATA_WIDTH), .DELAY_DEPTH(DELAY_DEPTH)) dut (
    .tclk(clk), .rst_n(rst_n), .i_tdata(i_tdata), .i_tvalid(i_tvalid), .i_tready(i_tready),
    .o_tready(o_tready), .o_tvalid(o_tvalid), .o_tdata(o_tdata), .rate(rate), .depth(depth),
    .mix(mix), .makeup_gain(makeup_gain)
  );

  initial begin clk = 1'b0; forever #5 clk = ~clk; end
  initial begin
    $dumpfile("chorus_eff_tester.vcd");
    $dumpvars(0, chorus_eff_tester);
  end

  initial begin
    // ======= Reset with safe (unity/bypass) parameters =======
    rst_n = 1'b0; i_tdata = 0; i_tvalid = 1'b0; o_tready = 1'b0;
    rate = 16'h0000; depth = 16'h0000; mix = 16'h0000; makeup_gain = 16'h2000;
    #50;
    rst_n = 1'b1;

    // ======= Configure audible chorus (48 kHz) =======
    rate = 16'h015E;        // ~1 Hz LFO
    depth = 16'h2000;       // +/-128 smp (~2.7 ms) sweep
    mix = 16'h8000;         // 50/50 dry/wet
    makeup_gain = 16'h2D41; // +3 dB, restores 50/50 decorrelated mix

    fd_in = $fopen("../data/input.hex", "r");
    if (!fd_in) begin $display("[ERROR] Could not open input.hex"); $finish; end
    fd_out = $fopen("../data/hex/chorus-output.hex", "w");
    if (!fd_out) begin $display("[ERROR] Could not open output"); $finish; end

    // ======= Print configuration =======
    $display("========================================");
    $display("  CHORUS EFFECT TESTER");
    $display("========================================");
    $display("  Module:          chorus");
    $display("  Pipeline:        1 (registered output)");
    $display("  rate:            %04h  ~1 Hz LFO", rate);
    $display("  depth:           %04h  Q0.16, +/-128 smp", depth);
    $display("  mix:             %04h  Q0.16, 50/50", mix);
    $display("  makeup_gain:     %04h  Q2.13, +3 dB", makeup_gain);
    $display("  Input:           input.hex");
    $display("  Output:          chorus-output.hex");
    $display("========================================");

    num_samples = 0;
    while (!$feof(fd_in) && num_samples < 262144) begin
      scan_result = $fscanf(fd_in, "%h\n", hex_val);
      if (scan_result == 1) begin sample_mem[num_samples] = hex_val; num_samples = num_samples + 1; end
    end
    $fclose(fd_in);
    if (num_samples == 0) begin $fclose(fd_out); $finish; end

    i_tdata = sample_mem[0]; i_tvalid = 1'b1; o_tready = 1'b1; sample_count = 0;
    for (i = 0; i < num_samples; i = i + 1) begin
      @(posedge clk); #1;
      if (o_tvalid && o_tready) begin
        $fwrite(fd_out, "%06h\n", o_tdata);
        sample_count = sample_count + 1;
      end
      if (i + 1 < num_samples) i_tdata = sample_mem[i + 1];
    end
    i_tvalid = 1'b0;
    $fclose(fd_out);
    $display("  Wrote %0d samples to chorus-output.hex", sample_count);
    $display("========================================");
    $display("  PROCESSING COMPLETE");
    $display("========================================");
    #50; $finish;
  end
endmodule
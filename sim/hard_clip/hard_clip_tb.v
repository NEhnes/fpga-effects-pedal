`timescale 1ns / 1ps
`include "hard_clip.v"

module hard_clip_tb();

  // ======= GLOBAL CLOCK AND RESET =======
  reg clk;
  reg rst_n;

  // ======= DUT SIGNALS (AXI-STREAM) =======
  reg  signed [23:0] i_tdata;
  reg                i_tvalid;
  wire               i_tready;

  reg                o_tready;
  wire               o_tvalid;
  wire signed [23:0] o_tdata;

  // ======= DUT EFFECT PARAMETERS (Q-FORMAT) =======
  reg [15:0] input_gain;         // Q1.14 (unity = 0x4000)
  reg [15:0] normalized_clip;    // Q0.16 (+/- 1.0)

  // ======= GLOBAL TEST CONTROL VARIABLES =======
  integer num_pass;
  integer num_fail;

  // ======= PER-TEST VARIABLES =======
  integer gain_2x_upper;
  integer gain_2x_lower;
  integer gain_clip_upper;
  integer gain_clip_lower;

  // ======= FAILURE LOG =======
  reg [512:0] failed_tests [15:0];  // Store failure details
  integer num_failed_logged;

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
    $dumpfile("hard_clip_tb.vcd");
    $dumpvars(0, hard_clip_tb);
  end

  // ======= RESET TASK =======
  task reset;
  begin
    rst_n = 1'b0;
    i_tdata = 24'h000000;
    i_tvalid = 1'b0;
    o_tready = 1'b0;
    input_gain = 16'h0000;
    normalized_clip = 16'h0000;
    #50;
    rst_n = 1'b1;
  end
  endtask

  // ======= TEST 1: RESET CLEARS OUTPUT =======
  task test_1_reset_clears_output;
  begin
    wait(rst_n == 1'b1);
    #10;

    if (o_tdata == 24'h000000) begin
      $display("[PASS] Test 1: Reset clears output");
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test 1: Reset clears output");
      $display("       expected: 0x000000, got: 0x%06h (%d)", o_tdata, o_tdata);
      num_fail = num_fail + 1;
      failed_tests[num_failed_logged] = "Test 1: Reset output not cleared";
      num_failed_logged = num_failed_logged + 1;
    end
  end
  endtask

  // ======= TEST 2: AXI HANDSHAKE PROPAGATION =======
  task test_2_axi_handshake;
  begin
    wait(rst_n == 1'b1);
    #10;

    @(posedge clk) begin
      i_tdata = 24'h100000;
      i_tvalid = 1'b1;
      o_tready = 1'b1;
      input_gain = 16'h4000;        // Unity gain (Q1.14)
      normalized_clip = 16'h7FFF;   // High threshold (no clipping)
    end

    @(posedge clk);

    if (o_tvalid == 1'b1) begin
      $display("[PASS] Test 2a: o_tvalid propagates");
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test 2a: o_tvalid propagates");
      $display("       expected: 1'b1, got: %b", o_tvalid);
      num_fail = num_fail + 1;
      failed_tests[num_failed_logged] = "Test 2a: o_tvalid not asserted";
      num_failed_logged = num_failed_logged + 1;
    end

    if (i_tready == 1'b1) begin
      $display("[PASS] Test 2b: i_tready propagates");
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test 2b: i_tready propagates");
      $display("       expected: 1'b1, got: %b", i_tready);
      num_fail = num_fail + 1;
      failed_tests[num_failed_logged] = "Test 2b: i_tready not asserted";
      num_failed_logged = num_failed_logged + 1;
    end
  end
  endtask

  // ======= TEST 3: UNITY GAIN PASSTHROUGH (NO CLIPPING) =======
  task test_3_unity_gain_passthrough;
  begin
    wait(rst_n == 1'b1);
    #10;

    @(posedge clk) begin
      i_tdata = 24'h100000;
      i_tvalid = 1'b1;
      o_tready = 1'b1;
      input_gain = 16'h4000;        // Unity Q1.14
      normalized_clip = 16'h7FFF;   // High threshold (no clipping)
    end

    // Wait for pipeline: gain stage + clip stage + register
    @(posedge clk);
    @(posedge clk);

    if (o_tdata == 24'h100000) begin
      $display("[PASS] Test 3: Unity gain passthrough");
      $display("       in: 0x100000, out: 0x%06h", o_tdata);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test 3: Unity gain passthrough");
      $display("       in: 0x100000, expected: 0x100000, got: 0x%06h (%d)", o_tdata, o_tdata);
      num_fail = num_fail + 1;
      failed_tests[num_failed_logged] = "Test 3: Unity gain produced wrong output";
      num_failed_logged = num_failed_logged + 1;
    end
  end
  endtask

  // ======= TEST 4: ~2X GAIN AMPLIFICATION =======
  task test_4_2x_gain;
  begin
    wait(rst_n == 1'b1);
    #10;

    @(posedge clk) begin
      i_tdata = 24'h080000;
      i_tvalid = 1'b1;
      o_tready = 1'b1;
      input_gain = 16'h7FFF;        // ~+2.0x in signed Q1.14
      normalized_clip = 16'h7FFF;   // No clip
    end

    @(posedge clk);
    @(posedge clk);

    // Calculate tolerance band for fixed-point approximation
    gain_2x_upper = $signed(24'h0FFFF8) * 1.05;
    gain_2x_lower = $signed(24'h0FFFF8) * 0.95;

    if (o_tdata >= gain_2x_lower && o_tdata <= gain_2x_upper) begin
      $display("[PASS] Test 4: ~2x gain amplification");
      $display("       in: 0x080000, out: 0x%06h (~2x amplified)", o_tdata);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test 4: ~2x gain amplification");
      $display("       in: 0x080000, expected: ~0x0FFFF8 (%d±5%%), got: 0x%06h (%d)",
               $signed(24'h0FFFF8), o_tdata, o_tdata);
      num_fail = num_fail + 1;
      failed_tests[num_failed_logged] = "Test 4: 2x gain produced wrong output";
      num_failed_logged = num_failed_logged + 1;
    end
  end
  endtask

  // ======= TEST 5: CLIPPING AT POSITIVE THRESHOLD =======
  task test_5_positive_clipping;
  begin
    wait(rst_n == 1'b1);
    #10;

    @(posedge clk) begin
      i_tdata = 24'h600000;
      i_tvalid = 1'b1;
      o_tready = 1'b1;
      input_gain = 16'h4000;        // Unity
      normalized_clip = 16'h4000;   // Clip threshold scaled to 0x400000
    end

    @(posedge clk);
    @(posedge clk);

    if (o_tdata == 24'h400000) begin
      $display("[PASS] Test 5: Positive clipping");
      $display("       in: 0x600000, out: 0x%06h (clipped at threshold)", o_tdata);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test 5: Positive clipping");
      $display("       in: 0x600000, expected: 0x400000, got: 0x%06h (%d)", o_tdata, o_tdata);
      num_fail = num_fail + 1;
      failed_tests[num_failed_logged] = "Test 5: Positive clipping failed";
      num_failed_logged = num_failed_logged + 1;
    end
  end
  endtask

  // ======= TEST 6: CLIPPING AT NEGATIVE THRESHOLD =======
  task test_6_negative_clipping;
  begin
    wait(rst_n == 1'b1);
    #10;

    @(posedge clk) begin
      i_tdata = -24'h600000;
      i_tvalid = 1'b1;
      o_tready = 1'b1;
      input_gain = 16'h4000;        // Unity
      normalized_clip = 16'h4000;   // Clip threshold scaled to 0x400000
    end

    @(posedge clk);
    @(posedge clk);

    if (o_tdata == -24'h400000) begin
      $display("[PASS] Test 6: Negative clipping");
      $display("       in: -0x600000, out: 0x%06h (clipped at -threshold)", o_tdata);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test 6: Negative clipping");
      $display("       in: -0x600000, expected: -0x400000 (%d), got: 0x%06h (%d)",
               -$signed(24'h400000), o_tdata, o_tdata);
      num_fail = num_fail + 1;
      failed_tests[num_failed_logged] = "Test 6: Negative clipping failed";
      num_failed_logged = num_failed_logged + 1;
    end
  end
  endtask

  // ======= TEST 7: BACKPRESSURE HANDLING =======
  task test_7_backpressure;
  begin
    wait(rst_n == 1'b1);
    #10;

    @(posedge clk) begin
      i_tdata = 24'h100000;
      i_tvalid = 1'b1;
      o_tready = 1'b0;              // Sink not ready
      input_gain = 16'h4000;
      normalized_clip = 16'h7FFF;
    end

    @(posedge clk);

    if (i_tready == 1'b0) begin
      $display("[PASS] Test 7: Backpressure handling");
      $display("       o_tready=0 -> i_tready=%b (correct)", i_tready);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test 7: Backpressure handling");
      $display("       o_tready=0, but i_tready=%b (should be 0)", i_tready);
      num_fail = num_fail + 1;
      failed_tests[num_failed_logged] = "Test 7: Backpressure not propagated";
      num_failed_logged = num_failed_logged + 1;
    end
  end
  endtask

  // ======= TEST 8: RESUME AFTER BACKPRESSURE =======
  task test_8_resume_after_backpressure;
  begin
    wait(rst_n == 1'b1);
    #10;

    // Apply backpressure
    @(posedge clk) begin
      o_tready = 1'b0;
    end

    @(posedge clk);

    // Release backpressure
    @(posedge clk) begin
      o_tready = 1'b1;
    end

    @(posedge clk);

    if (i_tready == 1'b1) begin
      $display("[PASS] Test 8: Resume after backpressure");
      $display("       o_tready=1 -> i_tready=%b (correct)", i_tready);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test 8: Resume after backpressure");
      $display("       o_tready=1, but i_tready=%b (should be 1)", i_tready);
      num_fail = num_fail + 1;
      failed_tests[num_failed_logged] = "Test 8: Failed to resume after backpressure";
      num_failed_logged = num_failed_logged + 1;
    end
  end
  endtask

  // ======= TEST 9: ZERO INPUT =======
  task test_9_zero_input;
  begin
    wait(rst_n == 1'b1);
    #10;

    @(posedge clk) begin
      i_tdata = 24'h000000;
      i_tvalid = 1'b1;
      o_tready = 1'b1;
      input_gain = 16'h4000;
      normalized_clip = 16'h7FFF;
    end

    @(posedge clk);
    @(posedge clk);

    if (o_tdata == 24'h000000) begin
      $display("[PASS] Test 9: Zero input");
      $display("       in: 0x000000, out: 0x%06h", o_tdata);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test 9: Zero input");
      $display("       in: 0x000000, expected: 0x000000, got: 0x%06h (%d)", o_tdata, o_tdata);
      num_fail = num_fail + 1;
      failed_tests[num_failed_logged] = "Test 9: Zero input produced non-zero output";
      num_failed_logged = num_failed_logged + 1;
    end
  end
  endtask

  // ======= TEST 10: COMBINED GAIN AND CLIP (NO CLIPPING) =======
  task test_10_gain_then_clip_no_clipping;
  begin
    wait(rst_n == 1'b1);
    #10;

    @(posedge clk) begin
      i_tdata = 24'h100000;
      i_tvalid = 1'b1;
      o_tready = 1'b1;
      input_gain = 16'h7FFF;        // ~+2x gain in signed Q1.14
      normalized_clip = 16'h7FFF;   // High threshold (no clipping)
    end

    // Calculate tolerance band
    gain_clip_upper = $signed(24'h1FFFF0) * 1.05;
    gain_clip_lower = $signed(24'h1FFFF0) * 0.95;

    @(posedge clk);
    @(posedge clk);

    if (o_tdata >= gain_clip_lower && o_tdata <= gain_clip_upper) begin
      $display("[PASS] Test 10: Gain then clip (no clipping)");
      $display("       in: 0x100000, out: 0x%06h (~2x amplified, no clip)", o_tdata);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test 10: Gain then clip (no clipping)");
      $display("       in: 0x100000, expected: ~0x1FFFF0 (%d±5%%), got: 0x%06h (%d)",
               $signed(24'h1FFFF0), o_tdata, o_tdata);
      num_fail = num_fail + 1;
      failed_tests[num_failed_logged] = "Test 10: Gain+clip produced wrong output";
      num_failed_logged = num_failed_logged + 1;
    end
  end
  endtask

  // ======= TEST SEQUENCE =======
  initial begin
    num_pass = 0;
    num_fail = 0;
    num_failed_logged = 0;

    reset;
    test_1_reset_clears_output;

    reset;
    test_2_axi_handshake;

    reset;
    test_3_unity_gain_passthrough;

    reset;
    test_4_2x_gain;

    reset;
    test_5_positive_clipping;

    reset;
    test_6_negative_clipping;

    reset;
    test_7_backpressure;

    reset;
    test_8_resume_after_backpressure;

    reset;
    test_9_zero_input;

    reset;
    test_10_gain_then_clip_no_clipping;

    #50;  // Final settling
  end

  // ======= TIMEOUT AND SUMMARY =======
  initial begin
    #5000;  // 5µs max simulation time

    $display("\n");
    $display("=====================================");
    $display("          TEST SUMMARY REPORT        ");
    $display("=====================================");
    $display("  Total Passed: %d", num_pass);
    $display("  Total Failed: %d", num_fail);
    $display("=====================================");

    if (num_fail > 0) begin
      $display("\n");
      $display("FAILURE DETAILS:");
      $display("-------------------------------------");

      // Print each logged failure
      for (integer i = 0; i < num_failed_logged; i = i + 1) begin
        $display("  [%d] %0s", i + 1, failed_tests[i]);
      end

      $display("-------------------------------------");
      $display("Review [FAIL] lines above for");
      $display("detailed comparison values.");
    end else begin
      $display("\n");
      $display("*** ALL TESTS PASSED ***");
    end

    $display("\n");

    $finish;
  end

endmodule
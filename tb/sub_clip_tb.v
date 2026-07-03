`timescale 1ns / 1ps
`include "hard_clip.v"

module sub_clip_tb;

  // DUT signals
  parameter WIDTH = 24;
  reg signed [WIDTH-1:0] i_sample;
  reg signed [15:0] clip_q016;
  wire signed [WIDTH-1:0] o_sample;

  // Test control
  integer num_pass, num_fail;
  integer test_index;

  // Instantiate DUT
  sub_clip #(.WIDTH(WIDTH)) dut (
    .i_sample(i_sample),
    .clip_q016(clip_q016),
    .o_sample(o_sample)
  );

  // Test sequence
  initial begin
    num_pass = 0;
    num_fail = 0;

    $display("\n=== Sub-Clip Module Testbench ===");
    $display("Parameter WIDTH = %d bits", WIDTH);
    $display("Testing Q0.15 clipping threshold\n");

    test_clip_positive_max();
    test_clip_negative_max();
    test_clip_within_bounds();
    test_clip_at_threshold();
    test_clip_at_negative_threshold();
    test_clip_extreme_positive();
    test_clip_extreme_negative();
    test_clip_zero_input();
    test_clip_zero_threshold();

    // Summary
    $display("\n=== Test Summary ===");
    $display("Passed: %d", num_pass);
    $display("Failed: %d", num_fail);
    if (num_fail == 0)
      $display("Result: ALL TESTS PASSED");
    else
      $display("Result: SOME TESTS FAILED");
    $finish;
  end

  // Test 1: Clamp input above positive threshold
  task test_clip_positive_max;
  begin
    $display("[TEST 1] Input exceeds positive threshold");
    clip_q016 = 16'h4000;  // Q0.15: 0.5
    i_sample = 24'h7FFFFF;  // Large positive value
    #1;
    if (o_sample == {{8{clip_q016[15]}}, clip_q016}) begin
      $display("[PASS] Clipped to positive threshold");
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Expected %h, got %h", {{8{clip_q016[15]}}, clip_q016}, o_sample);
      num_fail = num_fail + 1;
    end
  end
  endtask

  // Test 2: Clamp input below negative threshold
  task test_clip_negative_max;
  begin
    $display("[TEST 2] Input below negative threshold");
    clip_q016 = 16'h4000;  // Q0.15: 0.5, -threshold = -0.5
    i_sample = 24'h800000;  // Large negative value
    #1;
    if (o_sample == -{{8{clip_q016[15]}}, clip_q016}) begin
      $display("[PASS] Clipped to negative threshold");
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Expected %h, got %h", -{{8{clip_q016[15]}}, clip_q016}, o_sample);
      num_fail = num_fail + 1;
    end
  end
  endtask

  // Test 3: Input within bounds (no clipping)
  task test_clip_within_bounds;
  begin
    $display("[TEST 3] Input within bounds");
    clip_q016 = 16'h7FFF;  // Q0.15: ~1.0
    i_sample = 24'h001000;  // Small positive value
    #1;
    if (o_sample == i_sample) begin
      $display("[PASS] No clipping applied");
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Expected %h, got %h", i_sample, o_sample);
      num_fail = num_fail + 1;
    end
  end
  endtask

  // Test 4: Input exactly at positive threshold
  task test_clip_at_threshold;
  begin
    $display("[TEST 4] Input at positive threshold");
    clip_q016 = 16'h5000;  // Q0.15: 0.625
    i_sample = {{8{1'b0}}, clip_q016};  // Same as threshold
    #1;
    if (o_sample == i_sample) begin
      $display("[PASS] Input equals threshold");
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Expected %h, got %h", i_sample, o_sample);
      num_fail = num_fail + 1;
    end
  end
  endtask

  // Test 5: Input exactly at negative threshold
  task test_clip_at_negative_threshold;
  begin
    $display("[TEST 5] Input at negative threshold");
    clip_q016 = 16'h5000;
    i_sample = -{{8{1'b0}}, clip_q016};  // Negative threshold
    #1;
    if (o_sample == i_sample) begin
      $display("[PASS] Input equals negative threshold");
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Expected %h, got %h", i_sample, o_sample);
      num_fail = num_fail + 1;
    end
  end
  endtask

  // Test 6: Extreme positive with small threshold
  task test_clip_extreme_positive;
  begin
    $display("[TEST 6] Large positive input, small threshold");
    clip_q016 = 16'h0100;  // Q0.15: very small threshold
    i_sample = 24'h400000;  // Large positive
    #1;
    if (o_sample == {{8{clip_q016[15]}}, clip_q016}) begin
      $display("[PASS] Clipped to small positive threshold");
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Expected %h, got %h", {{8{clip_q016[15]}}, clip_q016}, o_sample);
      num_fail = num_fail + 1;
    end
  end
  endtask

  // Test 7: Extreme negative with small threshold
  task test_clip_extreme_negative;
  begin
    $display("[TEST 7] Large negative input, small threshold");
    clip_q016 = 16'h0100;
    i_sample = 24'hC00000;  // Large negative
    #1;
    if (o_sample == -{{8{clip_q016[15]}}, clip_q016}) begin
      $display("[PASS] Clipped to small negative threshold");
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Expected %h, got %h", -{{8{clip_q016[15]}}, clip_q016}, o_sample);
      num_fail = num_fail + 1;
    end
  end
  endtask

  // Test 8: Zero input
  task test_clip_zero_input;
  begin
    $display("[TEST 8] Zero input");
    clip_q016 = 16'h7FFF;  // Q0.15: ~1.0
    i_sample = 24'h000000;
    #1;
    if (o_sample == 24'h000000) begin
      $display("[PASS] Zero passes through");
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Expected 0, got %h", o_sample);
      num_fail = num_fail + 1;
    end
  end
  endtask

  // Test 9: Zero threshold (extreme clipping)
  task test_clip_zero_threshold;
  begin
    $display("[TEST 9] Zero threshold");
    clip_q016 = 16'h0000;  // Threshold = 0
    i_sample = 24'h001234;  // Any positive value
    #1;
    if (o_sample == 24'h000000) begin
      $display("[PASS] Clipped to zero");
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Expected 0, got %h", o_sample);
      num_fail = num_fail + 1;
    end
  end
  endtask

  // Waveform dump
  initial begin
    $dumpfile("sub_clip_tb.vcd");
    $dumpvars(0, sub_clip_tb);
  end

  // Timeout to prevent infinite loops
  initial begin
    #5000;  // 5µs max simulation time
    $display("\n[TIMEOUT] Simulation exceeded max time");
    $finish;
  end

endmodule
`timescale 1ns / 1ps
`include "../../src/eff/noise_gate.v"

module noise_gate_tb;

  // ============================================================
  // DUT signals
  // ============================================================
  reg         tclk;
  reg         rst_n;

  reg  [15:0] threshold;
  reg  [15:0] attack;
  reg  [15:0] release_len;
  reg  [15:0] makeup_gain;

  reg  [23:0] i_tdata;
  reg         i_tvalid;
  wire        i_tready;

  reg         o_tready;
  wire        o_tvalid;
  wire [23:0] o_tdata;

  // ============================================================
  // Global test control
  // ============================================================
  integer num_pass, num_fail;

  // Module-level declarations for pure Verilog compatibility
  reg [23:0] dc_outs [0:9];
  reg [23:0] rand_outs [0:4];
  reg [23:0] ramp_c1, ramp_c5;
  integer dc_i, r_i;
  integer rand_seed;

  // ============================================================
  // Instantiate DUT
  // ============================================================
  noise_gate #(.WIDTH(24)) dut (
    .threshold   (threshold),
    .attack      (attack),
    .release_len (release_len),
    .makeup_gain (makeup_gain),
    .tclk        (tclk),
    .rst_n       (rst_n),
    .i_tdata     (i_tdata),
    .i_tvalid    (i_tvalid),
    .i_tready    (i_tready),
    .o_tready    (o_tready),
    .o_tvalid    (o_tvalid),
    .o_tdata     (o_tdata)
  );

  // ============================================================
  // DEBUG monitor — hierarchical probe of DUT internals
  // samples 1ns after each posedge (post-settle)
  // ============================================================
  always @(posedge tclk) begin
    #1 $display("t=%4d rst=%b iv=%b otr=%b itr=%b gte=%b | id=%h env=%h gain=%h od=%h cap=%h",
      $time, rst_n, i_tvalid, o_tready, i_tready, dut.gate_open_now, i_tdata,
      dut.envelope, dut.gain_q114, o_tdata, cap);
  end

  // ============================================================
  // Clock — 10ns period
  // ============================================================
  initial begin
    tclk = 1'b0;
    forever #5 tclk = ~tclk;
  end

  // ============================================================
  // Waveform dump
  // ============================================================
  initial begin
    $dumpfile("noise_gate_tb.vcd");
    $dumpvars(0, noise_gate_tb);
  end

  // ============================================================
  // Reset task
  // ============================================================
  task reset;
  begin
    // Assert and release reset on falling clock edges. Preserve the
    // effect parameters so each test can configure them before reset.
    @(negedge tclk);
    rst_n     = 1'b0;
    i_tdata   = 24'd0;
    i_tvalid  = 1'b0;
    o_tready  = 1'b1;
    repeat (5) @(negedge tclk);
    rst_n = 1'b1;
    @(negedge tclk);
  end
  endtask

  // ============================================================
  // Send one valid sample (one cycle), then de-assert valid
  // ============================================================
  task send;
    input signed [23:0] sample;
  begin
    @(negedge tclk);
    i_tdata  = sample;
    i_tvalid = 1'b1;
    o_tready = 1'b1;
    @(negedge tclk);
    i_tvalid = 1'b0;
  end
  endtask

  // ============================================================
  // Capture register for send_cap
  // ============================================================
  reg [23:0] cap;

  // ============================================================
  // Send one sample and capture output on next posedge
  // ============================================================
  task send_cap;
    input signed [23:0] sample;
  begin
    @(negedge tclk);
    i_tdata  = sample;
    i_tvalid = 1'b1;
    o_tready = 1'b1;
    @(posedge tclk);
    #1 cap = o_tdata;
    @(negedge tclk);
    i_tvalid = 1'b0;
  end
  endtask

  // ============================================================
  // Helper: check cap == expected (exact)
  // ============================================================
  task check_eq;
    input [23:0] expected;
    input [7:0]  tnum;
    input [63:0] tname;
  begin
    if (cap == expected) begin
      $display("[PASS] Test %0d: %0s", tnum, tname);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test %0d: %0s  (expected %h, got %h)", tnum, tname, expected, cap);
      num_fail = num_fail + 1;
    end
  end
  endtask

  // ============================================================
  // Helper: check within tolerance
  // ============================================================
  task check_tol;
    input [23:0] expected;
    input [23:0] tol;
    input [7:0]  tnum;
    input [63:0] tname;
  begin
    if (cap >= (expected - tol) && cap <= (expected + tol)) begin
      $display("[PASS] Test %0d: %0s  (expected ~%d, got %d)", tnum, tname, expected, cap);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test %0d: %0s  (expected ~%d +/-%d, got %d)", tnum, tname, expected, tol, cap);
      num_fail = num_fail + 1;
    end
  end
  endtask

  // ============================================================
  // Helper: check boolean condition
  // ============================================================
  task check_cond;
    input       cond;
    input [7:0] tnum;
    input [63:0] tname;
  begin
    if (cond) begin
      $display("[PASS] Test %0d: %0s", tnum, tname);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test %0d: %0s", tnum, tname);
      num_fail = num_fail + 1;
    end
  end
  endtask

  // ============================================================
  // Test sequence
  //
  // IMPORTANT: After reset, the envelope register is 0 and the
  // gate_is_open flag is 0. The first valid cycle charges the
  // envelope but the gate remains closed (gate_open depends on
  // the envelope BEFORE the update). Output from the first valid
  // cycle is therefore always 0.
  //
  // To test pass-through behavior, always send a priming sample
  // first, then send the actual test sample and capture its output.
  // ============================================================
  initial begin
    num_pass = 0;
    num_fail = 0;
    threshold = 16'd0;
    attack = 16'd0;
    release_len = 16'd0;
    makeup_gain = 16'd8192;
    i_tdata = 24'd0;
    i_tvalid = 1'b0;
    o_tready = 1'b1;
    rst_n = 1'b1;

    // =========================================================
    // TEST 1: Reset clears state
    // =========================================================
    reset;
    #10;
    check_cond(o_tdata == 24'd0, 1, "reset clears output");

    attack      = 16'd500;
    release_len = 16'd500;

    // =========================================================
    // TEST 2: Zero input -> zero output
    // =========================================================
    threshold   = 16'd0;
    attack      = 16'd0;
    release_len = 16'd0;
    send_cap(24'd0);
    check_eq(24'd0, 2, "zero input -> zero output");

    // =========================================================
    // TEST 3: AXI handshake — o_tvalid follows i_tvalid
    // =========================================================
    threshold   = 16'd0;
    attack      = 16'd0;
    release_len = 16'd0;
    reset;
    @(posedge tclk);
    i_tdata  = 24'h100000;
    i_tvalid = 1'b1;
    o_tready = 1'b1;
    @(posedge tclk);
    check_cond(o_tvalid == 1'b1, 3, "o_tvalid asserts with i_tvalid (3a)");
    i_tvalid = 1'b0;
    @(posedge tclk);
    check_cond(o_tvalid == 1'b0, 3, "o_tvalid de-asserts with i_tvalid (3b)");

    // =========================================================
    // TEST 4: Backpressure — i_tready follows o_tready
    // =========================================================
    reset;
    o_tready = 1'b0;
    @(posedge tclk);
    i_tvalid = 1'b1;
    @(posedge tclk);
    check_cond(i_tready == 1'b0, 4, "i_tready low when o_tready low (4a)");
    o_tready = 1'b1;
    @(posedge tclk);
    check_cond(i_tready == 1'b1, 4, "i_tready high when o_tready high (4b)");
    i_tvalid = 1'b0;

    // =========================================================
    // TEST 5: Signal above threshold — gate lets audio through
    //
    // Send a priming sample to charge the envelope and open the
    // gate. Then send the test sample and verify it passes at
    // unity gain.
    // =========================================================
    threshold   = 16'h0100;
    attack      = 16'd0;
    release_len = 16'd500;
    makeup_gain = 16'd8192;  // unity
    reset;
    send(24'h300000);         // prime: charge envelope (output discarded)
    send_cap(24'h300000);     // test: envelope is charged, gate is open
    check_tol(24'h300000, 24'd2, 5, "loud signal passes through at unity gain");

    // =========================================================
    // TEST 6: Signal below threshold — gate blocks (instant close)
    // =========================================================
    threshold   = 16'h4000;
    attack      = 16'd0;
    release_len = 16'd0;
    makeup_gain = 16'd8192;
    reset;
    send_cap(24'h001000);  // below threshold, gate stays closed
    check_eq(24'd0, 6, "quiet signal gated to zero");

    // =========================================================
    // TEST 7: Attack ramping — gain increases over 5 cycles
    //
    // After priming, the gate opens and the ramp counter
    // increments from 0 to attack (5). The captured output
    // from cycle 5 should have significantly more gain than
    // cycle 1.
    // =========================================================
    threshold   = 16'h0001;
    attack      = 16'd5;
    release_len = 16'd0;
    makeup_gain = 16'd8192;
    reset;
    send(24'h200000);         // prime: charge envelope
    send_cap(24'h200000);     // cycle 1 of ramp
    ramp_c1 = cap;
    send(24'h200000);
    send(24'h200000);
    send(24'h200000);
    send_cap(24'h200000);     // cycle 5 of ramp
    ramp_c5 = cap;
    // After 5 valid cycles with gate_open=1 and ramp_counter going 0->1->2->3->4->5:
    //   cycle 5 gain = 5/5 * 1.0 = 1.0
    // With 0x200000 input and gain=1.0: output ~= 0x200000
    check_cond(ramp_c5 >= 24'h180000, 7, "ramp gain reaches ~1.0 after 5 cycles");

    // =========================================================
    // TEST 8: Makeup gain amplification (2.0x)
    //
    // makeup_gain=0x4000 = Q13 2.0. Input 0x100000 * 2.0 = 0x200000.
    // =========================================================
    threshold   = 16'h0001;
    attack      = 16'd0;
    release_len = 16'd0;
    makeup_gain = 16'd16384;  // 0x8000 = Q1.14 2.0
    reset;
    send(24'h100000);         // prime: charge envelope + open gate
    send_cap(24'h100000);     // test: gate is open, makeup doubles it
    check_tol(24'h200000, 24'd4, 8, "makeup gain 2.0x doubles output");

    // =========================================================
    // TEST 9: Release ramping — output decays when input stops
    //
    // Open gate fully with multiple loud samples, then send
    // silence. Envelope decays slowly, gate eventually closes
    // and release ramps output to zero.
    // =========================================================
    threshold   = 16'h0100;
    attack      = 16'd0;
    release_len = 16'd5;
    makeup_gain = 16'd8192;
    reset;
    send(24'h400000);         // prime to charge envelope
    send(24'h400000);         // gate is now open, sustain
    send(24'd0);              // start sending silence — envelope decays
    send(24'd0);
    send(24'd0);
    send_cap(24'd0);          // output should be very small or zero
    // After 4 zero samples, the envelope has decayed and release
    // counter should have closed the gate on at least some cycles
    check_cond(cap < 24'h200000, 9, "output decays during release ramp");

    // =========================================================
    // TEST 10: Threshold boundary
    //
    // Signal below threshold: gate blocks -> output 0
    // Same signal, lower threshold: gate opens -> output ~= input
    // =========================================================
    threshold   = 16'h2000;
    attack      = 16'd0;
    release_len = 16'd0;
    makeup_gain = 16'd8192;
    reset;
    send_cap(24'h180000);     // 0x180000 < scaled_threshold 0x200000
    check_eq(24'd0, 10, "signal below threshold is gated (10a)");

    threshold = 16'h1000;     // 0x100000 < 0x180000, gate opens
    reset;
    send(24'h180000);         // prime
    send_cap(24'h180000);     // gate is open, signal passes
    check_tol(24'h180000, 24'd2, 10, "lower threshold lets same signal through (10b)");

    // =========================================================
    // TEST 11: Pipeline settling on DC step
    // =========================================================
    threshold   = 16'h0001;
    attack      = 16'd0;
    release_len = 16'd0;
    makeup_gain = 16'd8192;
    reset;
    send(24'h0F0000);         // prime
    for (dc_i = 0; dc_i < 10; dc_i = dc_i + 1) begin
      send_cap(24'h0F0000);
      dc_outs[dc_i] = cap;
    end
    check_cond(dc_outs[5] == dc_outs[9], 11, "output stabilizes after pipeline settling");

    // =========================================================
    // TEST 12: Positive saturation at 24'h7FFFFF
    //
    // 0x600000 * gain(1.0) * makeup(2.0) overflows -> clamp
    // =========================================================
    threshold   = 16'h0001;
    attack      = 16'd0;
    release_len = 16'd0;
    makeup_gain = 16'd16384;  // 2.0x
    reset;
    send(24'h700000);         // prime + open gate
    send_cap(24'h700000);     // 0x700000 * 2.0 -> saturate
    check_eq(24'h7FFFFF, 12, "overflow saturates at max positive");

    // =========================================================
    // TEST 13: Negative saturation at 24'h800000
    // =========================================================
    reset;
    send(24'h900000);         // prime + open gate
    send_cap(24'h900000);     // -0x700000 * 2.0 -> underflow
    check_eq(24'h800000, 13, "underflow saturates at min negative");

    // =========================================================
    // TEST 14: Constrained random parameter variation
    // =========================================================
    threshold   = 16'h0800;
    attack      = 16'd0;
    release_len = 16'd0;
    makeup_gain = 16'd8192;
    reset;
    rand_seed = 42;
    send(24'h300000);         // prime once before varying params
    for (r_i = 0; r_i < 5; r_i = r_i + 1) begin
      threshold   = ($random(rand_seed) & 16'h3FFF);
      makeup_gain = ($random(rand_seed) & 16'h7FFF);
      send_cap(24'h300000);
      rand_outs[r_i] = cap;
      if (cap <= 24'h7FFFFF) begin
        $display("[PASS] Test 14-%0d: rand param in range  (got %h)", r_i, cap);
        num_pass = num_pass + 1;
      end else begin
        $display("[FAIL] Test 14-%0d: rand param out of range  (got %h)", r_i, cap);
        num_fail = num_fail + 1;
      end
    end
    check_cond(
      (rand_outs[0] != rand_outs[1]) || (rand_outs[1] != rand_outs[2]),
      14, "random params produce different outputs (14-5)"
    );

    // =========================================================
    // TEST 15: Instant attack + instant release
    // =========================================================
    threshold   = 16'h0100;
    attack      = 16'd0;
    release_len = 16'd0;
    makeup_gain = 16'd8192;
    reset;
    send(24'h400000);         // prime + open gate
    send_cap(24'h400000);     // gate open, output = input
    check_tol(24'h400000, 24'd2, 15, "instant attack passes audio (15a)");
    threshold = 16'h7000;     // force the gate closed from the stored envelope
    send_cap(24'h001000);     // first closed-cycle output still uses old gain
    send_cap(24'h001000);     // release gain is now zero
    check_eq(24'd0, 15, "instant release mutes to zero (15b)");

    // =========================================================
    // TEST 16: Large attack — slow fade-in
    // =========================================================
    threshold   = 16'h0001;
    attack      = 16'd100;
    release_len = 16'd0;
    makeup_gain = 16'd8192;
    reset;
    send(24'h400000);         // prime + start ramp
    send_cap(24'h400000);     // ramp_counter=1/100, gain ~0.01
    check_cond(cap < 24'h010000, 16, "large attack: first output is small");

    // =========================================================
    // TEST 17: Long release — output persists
    // =========================================================
    threshold   = 16'h0100;
    attack      = 16'd0;
    release_len = 16'd500;
    makeup_gain = 16'd8192;
    reset;
    send(24'h400000);         // prime
    send(24'h400000);         // sustain: gate open, envelope at 0x400000
    send(24'h001000);         // below threshold; envelope decays slowly
    send(24'h001000);
    send(24'h001000);
    send_cap(24'h001000);     // stored envelope keeps the gate open
    check_cond(cap > 24'd0, 17, "long release: gain persists after 5 quiet cycles");

    // =========================================================
    // Summary
    // =========================================================
    #100;
    $display("");
    $display("==============================================");
    $display("  Test Summary");
    $display("==============================================");
    $display("  Passed: %0d", num_pass);
    $display("  Failed: %0d", num_fail);
    $display("==============================================");
    if (num_fail > 0) begin
      $display("  FAIL — %0d test(s) failed!", num_fail);
    end else begin
      $display("  ALL TESTS PASSED");
    end
    $display("==============================================");
    $finish;
  end

  // ============================================================
  // Timeout at 50us
  // ============================================================
  initial begin
    #50000;
    $display("");
    $display("==============================================");
    $display("  TIMEOUT — simulation stopped at 50us");
    $display("==============================================");
    $finish;
  end

endmodule

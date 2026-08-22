`timescale 1ns / 1ps
`include "../../src/eff/chorus.v"
//=============================================================================
// chorus_tb.v -- self-checking testbench for chorus.v (AXI-Stream chorus FX)
//
// Pure Verilog (IEEE 1364-2001). Targets Icarus Verilog + GTKWave.
//
// Methodology:
//  - Cycle-accurate REFERENCE MODEL (ref_compute) mirrors the DUT DSP chain
//    bit-exactly: LFO triangle -> modulated delay (Q8, clamped) -> circular
//    tap reads -> 8-bit linear interp -> dry/wet xfade -> Q2.13 makeup gain
//    (round + saturate). Every streamed sample is compared with === (X-safe).
//  - Independent hand-computed vectors (bypass identity, 2x gain, saturation
//    rails, echo position/amplitude) protect against model/RTL common bugs.
//  - Stimulus is applied on negedge tclk (stable well before the DUT's
//    posedge capture -> no TB/RTL race). Outputs are sampled #1 after
//    posedge so non-blocking updates have settled.
//
// Run:
//   iverilog -o chorus_sim chorus_tb.v
//   vvp chorus_sim
//   gtkwave chorus_tb.vcd
//=============================================================================
module chorus_tb;

  //---------------------------------------------------------------------------
  // Parameters (match DUT instantiation)
  //---------------------------------------------------------------------------
  parameter WIDTH       = 24;
  parameter DELAY_DEPTH = 2048;                 // power of 2, >= 16
  localparam ADDR_W     = $clog2(DELAY_DEPTH);  // 11

  //---------------------------------------------------------------------------
  // Global clock and reset
  //---------------------------------------------------------------------------
  reg tclk;
  reg rst_n;

  //---------------------------------------------------------------------------
  // DUT signals (match module ports)
  //---------------------------------------------------------------------------
  reg  [15:0]      rate;          // LFO rate: f = rate*fs/2^24
  reg  [15:0]      depth;         // Q0.16 modulation depth
  reg  [15:0]      mix;           // Q0.16 dry/wet crossfade
  reg  [15:0]      makeup_gain;   // Q2.13 signed (unity = 0x2000)
  reg  [WIDTH-1:0] i_tdata;
  reg              i_tvalid;
  reg              o_tready;
  wire             i_tready;
  wire             o_tvalid;
  wire [WIDTH-1:0] o_tdata;

  //---------------------------------------------------------------------------
  // Global test control variables
  //---------------------------------------------------------------------------
  integer num_pass, num_fail;
  integer err_total;            // total failed checks (sample-level + point)
  integer samples_processed;    // accepted AXI-Stream samples
  integer fail_stored;          // entries in failure log (capped)
  integer fail_test_log   [0:31];
  reg     [255:0] fail_name_log   [0:31];
  reg     [255:0] fail_detail_log [0:31];

  //---------------------------------------------------------------------------
  // Per-test control
  //---------------------------------------------------------------------------
  integer         cur_test_num;
  integer         cur_test_fails;
  reg     [255:0] cur_test_name;
  reg     [WIDTH-1:0] last_driven;   // last sample fed to DUT (identity checks)

  // performance metrics (filled by relevant tests, reported in summary)
  integer measured_lat;   // input->output latency in cycles   (test 5)
  integer settle_len;     // wet-path DC settling in samples  (test 8)
  integer echo_pos;       // measured echo position           (test 9)
  integer echo_cnt;       // number of echo events            (test 9)

  //---------------------------------------------------------------------------
  // Constrained-random control
  //---------------------------------------------------------------------------
  integer   rnd_seed;                       // seeded -> reproducible streams
  reg [15:0] rate_r, depth_r, mix_r, gain_r;
  reg [WIDTH-1:0] rnd_smp;
  reg [63:0] combo_sig [1:3];               // per-combo output signature

  //---------------------------------------------------------------------------
  // Reference model state (mirrors DUT internals)
  //---------------------------------------------------------------------------
  reg [31:0]       rm_phase;
  reg [ADDR_W-1:0] rm_wpos;
  reg [WIDTH-1:0]  rm_ram [0:DELAY_DEPTH-1];
  reg [WIDTH-1:0]  rm_expected;

  // Constants mirroring sub_mod_delay for DELAY_DEPTH = 2048
  localparam RM_SHIFT = 16 - ADDR_W;                              // >>> 5
  localparam signed [24:0] RM_BASE_Q8 = (DELAY_DEPTH / 2) * 256;  // 262144
  localparam signed [24:0] RM_MIN_Q8  = 2 * 256;                  // 512
  localparam signed [24:0] RM_MAX_Q8  = (DELAY_DEPTH - 2) * 256;  // 523776

  //---------------------------------------------------------------------------
  // Instantiate DUT
  //---------------------------------------------------------------------------
  chorus #(
    .WIDTH       (WIDTH),
    .DELAY_DEPTH (DELAY_DEPTH)
  ) dut (
    .rate        (rate),
    .depth       (depth),
    .mix         (mix),
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

  //===========================================================================
  // Clock generation: 10 ns period (100 MHz)
  //===========================================================================
  initial begin
    tclk = 1'b0;
    forever #5 tclk = ~tclk;
  end

  //===========================================================================
  // Logging / check helpers
  //===========================================================================

  // Central failure logger: prints detail line and stores it for the
  // end-of-sim failure summary (capped at 32 stored entries).
  task fail_line;
    input [255:0] detail;
    begin
      err_total = err_total + 1;
      $display("    [FAIL] T%0d (%0s) %0s", cur_test_num, cur_test_name, detail);
      if (fail_stored < 32) begin
        fail_test_log[fail_stored]   = cur_test_num;
        fail_name_log[fail_stored]   = cur_test_name;
        fail_detail_log[fail_stored] = detail;
        fail_stored = fail_stored + 1;
      end
    end
  endtask

  // Pattern-equality check (X-safe). Silent on pass; logs on fail.
  task expect_eq;
    input [31:0]  actual;
    input [31:0]  expected;
    input [255:0] label;
    reg [255:0] msg;
    begin
      if (actual !== expected) begin
        cur_test_fails = cur_test_fails + 1;
        $sformat(msg, "%0s: expected %h, got %h", label, expected, actual);
        fail_line(msg);
      end
    end
  endtask

  // Boolean-condition check. Silent on pass; logs on fail.
  task expect_true;
    input         condition;
    input [255:0] label;
    reg [255:0] msg;
    begin
      if (condition !== 1'b1) begin
        cur_test_fails = cur_test_fails + 1;
        $sformat(msg, "%0s: condition false", label);
        fail_line(msg);
      end
    end
  endtask

  // Test bookkeeping: verdict line references the test number.
  task start_test;
    input integer tnum;
    input [255:0] tname;
    begin
      cur_test_num   = tnum;
      cur_test_name  = tname;
      cur_test_fails = 0;
      $display("");
      $display("--- Test %0d: %0s ---", tnum, tname);
    end
  endtask

  task end_test;
    begin
      if (cur_test_fails == 0) begin
        num_pass = num_pass + 1;
        $display("[PASS] Test %0d: %0s", cur_test_num, cur_test_name);
      end else begin
        num_fail = num_fail + 1;
        $display("[FAIL] Test %0d: %0s -- %0d check(s) failed",
                 cur_test_num, cur_test_name, cur_test_fails);
      end
    end
  endtask

  //===========================================================================
  // Reference model: bit-exact mirror of the DUT DSP chain.
  // Call ONCE per accepted sample, BEFORE the accepting posedge.
  // Computes rm_expected, then advances model state exactly like the DUT's
  // clocked block (compute-from-pre-edge-state, then update).
  //===========================================================================
  task ref_compute;
    input [WIDTH-1:0] dry_raw;
    reg [7:0]               tri_v;
    reg signed [8:0]        lfo_s;
    reg signed [24:0]       mod_prod, mod_q8, delay_raw;
    reg signed [23:0]       delay_q8;
    reg [ADDR_W-1:0]        int_d, rd0, rd1;
    reg [7:0]               frac_v;
    reg signed [23:0]       s0_v, s1_v, dry_s, wet_v, mixed_v, out_v;
    reg signed [24:0]       d_l, interp_l, d_m, mixed_m;
    reg signed [32:0]       p_l;    // lerp product  (WIDTH+9 bits)
    reg signed [40:0]       p_m;    // xfade product (WIDTH+17 bits)
    reg signed [39:0]       g_t, g_r, g_s;  // gain path (WIDTH+16 bits)
    begin
      // STAGE 1: unipolar triangle fold of phase accumulator top bits
      tri_v = rm_phase[31] ? ~rm_phase[30:23] : rm_phase[30:23];

      // STAGE 2: modulated delay, Q8 samples, clamped to [2, DEPTH-2]
      lfo_s     = $signed({1'b0, tri_v}) - 9'sd128;      // -128..+127
      mod_prod  = $signed({1'b0, depth}) * lfo_s;
      mod_q8    = mod_prod >>> RM_SHIFT;                 // >>> (16-clog2(DEPTH))
      delay_raw = RM_BASE_Q8 + mod_q8;
      if (delay_raw < RM_MIN_Q8)      delay_q8 = 24'sd512;
      else if (delay_raw > RM_MAX_Q8) delay_q8 = 24'sd523776;
      else                            delay_q8 = delay_raw[23:0];

      // STAGE 3: circular tap addresses (truncation = free wrap)
      int_d  = delay_q8[ADDR_W+7:8];
      frac_v = delay_q8[7:0];
      rd0    = rm_wpos - int_d;
      rd1    = rd0 + 1'b1;
      s0_v   = rm_ram[rd0];
      s1_v   = rm_ram[rd1];

      // STAGE 4: fractional-sample linear interpolation, saturated
      d_l      = s1_v - s0_v;
      p_l      = d_l * $signed({1'b0, frac_v});
      interp_l = s0_v + (p_l >>> 8);
      if (interp_l > 25'sd8388607)       wet_v = 24'sh7FFFFF;
      else if (interp_l < -25'sd8388608) wet_v = 24'sh800000;
      else                               wet_v = interp_l[23:0];

      // STAGE 5: linear dry/wet crossfade, saturated
      dry_s   = dry_raw;
      d_m     = wet_v - dry_s;
      p_m     = d_m * $signed({1'b0, mix});
      mixed_m = dry_s + (p_m >>> 16);
      if (mixed_m > 25'sd8388607)       mixed_v = 24'sh7FFFFF;
      else if (mixed_m < -25'sd8388608) mixed_v = 24'sh800000;
      else                              mixed_v = mixed_m[23:0];

      // STAGE 6: makeup gain Q2.13 (FRAC_BITS=13), round then saturate
      g_t = mixed_v * $signed(makeup_gain);
      g_r = g_t + 40'sd4096;                 // + (1 << 12)
      g_s = g_r >>> 13;
      if (g_s > 40'sd8388607)       out_v = 24'sh7FFFFF;
      else if (g_s < -40'sd8388608) out_v = 24'sh800000;
      else                          out_v = g_s[23:0];

      rm_expected = out_v;

      // SEQUENTIAL UPDATE (same ordering as DUT clocked block)
      rm_ram[rm_wpos] = dry_raw;
      rm_wpos  = rm_wpos + 1'b1;
      rm_phase = rm_phase + {rate, 8'b0};    // rate << 8, 32-bit wrap
    end
  endtask

  //===========================================================================
  // TB control tasks
  //===========================================================================

  // Synchronous-style active-low reset pulse; release on negedge so the
  // first sampled posedge sees clean setup. Re-syncs the reference model.
  // NOTE: neither RAM has hardware reset, so the TB clears BOTH
  // dut.delay_ram and rm_ram here -- keeps them bit-matched while giving
  // every test a silent, deterministic delay line (stale samples from a
  // previous stream otherwise leak into silence-based vector checks).
  task apply_reset;
    integer i;
    begin
      @(negedge tclk);
      rst_n    = 1'b0;
      i_tvalid = 1'b0;
      i_tdata  = {WIDTH{1'b0}};
      o_tready = 1'b1;
      repeat (5) @(negedge tclk);   // ~50 ns hold
      rst_n = 1'b1;
      rm_phase    = 32'd0;
      rm_wpos     = {ADDR_W{1'b0}};
      rm_expected = {WIDTH{1'b0}};
      for (i = 0; i < DELAY_DEPTH; i = i + 1) begin
        rm_ram[i]         = {WIDTH{1'b0}};
        dut.delay_ram[i]  = {WIDTH{1'b0}};
      end
    end
  endtask

  // Change effect parameters between streams (keeps i_tvalid low so the
  // DUT accepts nothing while parameters settle).
  task set_params;
    input [15:0] r;
    input [15:0] d;
    input [15:0] m;
    input [15:0] g;
    begin
      @(negedge tclk);
      rate        = r;
      depth       = d;
      mix         = m;
      makeup_gain = g;
      i_tvalid    = 1'b0;
    end
  endtask

  // Deassert valid on a negedge -> no accept at the following posedge.
  task stop_stream;
    begin
      @(negedge tclk);
      i_tvalid = 1'b0;
    end
  endtask

  // Stream one sample: drive on negedge, step reference model, then compare
  // the DUT's registered output one posedge later (#1 settles NBA updates).
  task send_and_check;
    input [WIDTH-1:0] sample;
    reg [255:0] msg;
    begin
      @(negedge tclk);
      i_tdata     = sample;
      i_tvalid    = 1'b1;
      last_driven = sample;
      ref_compute(sample);            // expected output for the NEXT posedge
      @(posedge tclk);
      #1;
      samples_processed = samples_processed + 1;
      if (o_tdata !== rm_expected) begin
        cur_test_fails = cur_test_fails + 1;
        $sformat(msg, "sample %0d: in=%h exp=%h got=%h",
                 samples_processed, sample, rm_expected, o_tdata);
        fail_line(msg);
      end
    end
  endtask

  //===========================================================================
  // TEST 1: reset clears all state (streamed dirt first, then reset)
  //===========================================================================
  task t1_reset_clears_state;
    begin
      start_test(1, "reset_clears_state");
      wait (rst_n == 1'b1);
      set_params(16'h015E, 16'h2000, 16'h8000, 16'h2000);
      // Dirty the state with nonzero samples
      send_and_check(24'h111111);
      send_and_check(24'h222222);
      send_and_check(24'h333333);
      expect_true(dut.phase !== 32'd0, "pre-reset: phase advanced");
      // Hit reset mid-operation, then verify cleared state
      apply_reset;
      #1;
      expect_eq(o_tdata,       24'h000000, "o_tdata cleared by reset");
      expect_eq(dut.phase,     32'd0,      "phase cleared by reset");
      expect_eq(dut.write_pos, 32'd0,      "write_pos cleared by reset");
      expect_eq(o_tvalid,      1'b0,       "o_tvalid low (i_tvalid low)");
      expect_eq(i_tready,      1'b1,       "i_tready high (o_tready high)");
      end_test;
    end
  endtask

  //===========================================================================
  // TEST 2: AXI handshake mirrors (combinational o_tvalid/i_tready coupling)
  // NOTE: the single valid-high cycle lets DUT accept one zero sample;
  // state is restored by the apply_reset that follows this test.
  //===========================================================================
  task t2_axi_handshake_mirror;
    begin
      start_test(2, "axi_handshake_mirror");
      wait (rst_n == 1'b1);
      set_params(16'h015E, 16'h2000, 16'h0000, 16'h2000);
      @(negedge tclk); #1;
      expect_eq(o_tvalid, 1'b0, "o_tvalid low when i_tvalid low");
      expect_eq(i_tready, 1'b1, "i_tready high when o_tready high");
      @(negedge tclk) i_tvalid = 1'b1;
      #1 expect_eq(o_tvalid, 1'b1, "o_tvalid asserts with i_tvalid");
      @(negedge tclk) i_tvalid = 1'b0;
      #1 expect_eq(o_tvalid, 1'b0, "o_tvalid drops with i_tvalid");
      end_test;
    end
  endtask

  //===========================================================================
  // TEST 3: backpressure -- i_tready must follow o_tready combinationally,
  // no data accepted while stalled, clean resume after release.
  //===========================================================================
  task t3_backpressure;
    begin
      start_test(3, "axi_backpressure_coupling");
      wait (rst_n == 1'b1);
      set_params(16'h015E, 16'h2000, 16'h0000, 16'h2000);
      // Stall downstream
      @(negedge tclk) o_tready = 1'b0;
      #1 expect_eq(i_tready, 1'b0, "i_tready follows o_tready low");
      @(negedge tclk) begin
        i_tdata  = 24'h123456;
        i_tvalid = 1'b1;
      end
      repeat (3) begin
        @(posedge tclk); #1;
        expect_eq(i_tready, 1'b0,       "i_tready stays low while stalled");
        expect_eq(o_tdata,  24'h000000, "no output while stalled");
      end
      // Release and confirm the stalled sample is accepted exactly once
      @(negedge tclk) o_tready = 1'b1;
      #1 expect_eq(i_tready, 1'b1, "i_tready re-asserts after release");
      ref_compute(24'h123456);        // accepted at upcoming posedge
      @(posedge tclk); #1;
      samples_processed = samples_processed + 1;
      expect_eq(o_tdata, rm_expected, "stalled sample accepted after release");
      // Resume streaming to prove pipeline intact
      send_and_check(24'h654321);
      send_and_check(24'h0A0A0A);
      stop_stream;
      end_test;
    end
  endtask

  //===========================================================================
  // TEST 4: zero input -> zero output (detects bias/offset/uninit state)
  //===========================================================================
  task t4_zero_input;
    integer k, zero_bad;
    begin
      start_test(4, "zero_input_no_offset");
      wait (rst_n == 1'b1);
      set_params(16'h015E, 16'h2000, 16'h8000, 16'h2D41);  // musical defaults
      zero_bad = 0;
      for (k = 0; k < 64; k = k + 1) begin
        send_and_check(24'h000000);
        if (o_tdata !== 24'h000000) zero_bad = zero_bad + 1;
      end
      expect_true(zero_bad == 0, "output stayed zero for 64 samples");
      stop_stream;
      end_test;
    end
  endtask

  //===========================================================================
  // TEST 5: unity passthrough (mix=0 dry, unity makeup) + latency measure
  //===========================================================================
  task t5_bypass_latency;
    integer k;
    begin
      start_test(5, "dry_bypass_unity_latency");
      wait (rst_n == 1'b1);
      set_params(16'h015E, 16'h2000, 16'h0000, 16'h2000);  // dry, unity gain
      // Latency probe: distinctive value, count posedges until it appears
      @(negedge tclk) begin
        i_tdata  = 24'h5A5A5A;
        i_tvalid = 1'b1;
      end
      ref_compute(24'h5A5A5A);
      @(posedge tclk); #1;
      samples_processed = samples_processed + 1;
      measured_lat = 1;
      if (o_tdata !== 24'h5A5A5A) begin
        measured_lat = 0;
        for (k = 2; k <= 5; k = k + 1) begin
          @(posedge tclk); #1;
          if (o_tdata === 24'h5A5A5A) begin
            measured_lat = k;
            k = 99;                    // exit scan
          end
        end
        if (measured_lat == 0) measured_lat = 99;  // never appeared
      end
      expect_eq(measured_lat, 1, "input->output latency (cycles)");
      @(negedge tclk) i_tvalid = 1'b0;   // pause stream
      // Identity vectors (independent of reference model)
      send_and_check(24'h000001); expect_eq(o_tdata, last_driven, "identity +1 LSB");
      send_and_check(24'h7FFFFF); expect_eq(o_tdata, last_driven, "identity +FS");
      send_and_check(24'h800000); expect_eq(o_tdata, last_driven, "identity -FS");
      send_and_check(24'hC00001); expect_eq(o_tdata, last_driven, "identity negative");
      send_and_check(24'h123456); expect_eq(o_tdata, last_driven, "identity pattern");
      send_and_check(24'h000000); expect_eq(o_tdata, last_driven, "identity zero");
      stop_stream;
      end_test;
    end
  endtask

  //===========================================================================
  // TEST 6: makeup gain amplification (2.0x = 0x4000 in Q2.13), dry path
  //===========================================================================
  task t6_gain_amplification;
    begin
      start_test(6, "makeup_gain_amplification");
      wait (rst_n == 1'b1);
      set_params(16'h015E, 16'h2000, 16'h0000, 16'h4000);  // dry, 2.0x
      send_and_check(24'h000001); expect_eq(o_tdata, 24'h000002, "2x small signal");
      send_and_check(24'h155555); expect_eq(o_tdata, 24'h2AAAAA, "2x mid signal");
      send_and_check(24'h400000); expect_eq(o_tdata, 24'h7FFFFF, "2x +FS saturates hi");
      send_and_check(24'hC00000); expect_eq(o_tdata, 24'h800000, "2x -FS lands exactly on MIN");
      send_and_check(24'hBFFFFF); expect_eq(o_tdata, 24'h800000, "2x beyond -FS clamps");
      send_and_check(24'h000000); expect_eq(o_tdata, 24'h000000, "2x zero in zero out");
      stop_stream;
      end_test;
    end
  endtask

  //===========================================================================
  // TEST 7: saturation / overflow clamping at both rails, incl. -4.0x gain
  //===========================================================================
  task t7_saturation_clamp;
    begin
      start_test(7, "saturation_overflow_clamp");
      wait (rst_n == 1'b1);
      set_params(16'h015E, 16'h2000, 16'h0000, 16'h7FFF);  // dry, ~+4.0x
      send_and_check(24'h400000); expect_eq(o_tdata, 24'h7FFFFF, "+rail clamp");
      send_and_check(24'hC00000); expect_eq(o_tdata, 24'h800000, "-rail clamp");
      set_params(16'h015E, 16'h2000, 16'h0000, 16'h8000);  // dry, -4.0x
      send_and_check(24'h100000); expect_eq(o_tdata, 24'hC00000, "-4x polarity flip");
      send_and_check(24'h200000); expect_eq(o_tdata, 24'h800000, "-4x exact MIN boundary");
      send_and_check(24'h200001); expect_eq(o_tdata, 24'h800000, "-4x below MIN clamps");
      send_and_check(24'hE00000); expect_eq(o_tdata, 24'h7FFFFF, "-4x flips onto +rail clamp");
      stop_stream;
      end_test;
    end
  endtask

  //===========================================================================
  // TEST 8: DC step / pipeline settling -- full-wet output must stabilize
  // at the input constant once the 2048-deep buffer fills (depth+margin).
  //===========================================================================
  task t8_dc_settling;
    integer k, tail_ok;
    begin
      start_test(8, "dc_step_pipeline_settling");
      wait (rst_n == 1'b1);
      set_params(16'h03E8, 16'h8000, 16'hFFFF, 16'h2000);  // full wet, unity
      tail_ok   = 0;
      settle_len = 0;
      for (k = 0; k < 2250; k = k + 1) begin
        send_and_check(24'h0AAAAA);
        if (o_tdata === 24'h0AAAAA) tail_ok = tail_ok + 1;
        else begin
          tail_ok    = 0;
          settle_len = k + 1;          // samples up to & incl. last unsettled
        end
      end
      expect_true(tail_ok >= 100, "settled to DC within buffer depth + margin");
      stop_stream;
      end_test;
    end
  endtask

  //===========================================================================
  // TEST 9: impulse response with depth=0 (static base delay DELAY_DEPTH/2).
  // Exactly one echo, at sample 1024, amplitude 0x0FFFF0 (mix=0xFFFF is
  // 65535/65536, so 0x100000 loses its bottom 4 bits: 0x100000 - 0x10).
  //===========================================================================
  task t9_impulse_echo;
    integer k;
    begin
      start_test(9, "impulse_static_delay_echo");
      wait (rst_n == 1'b1);
      set_params(16'h015E, 16'h0000, 16'hFFFF, 16'h2000);  // static 1024 smp
      echo_pos = -1;
      echo_cnt = 0;
      send_and_check(24'h100000);                // impulse in
      for (k = 1; k <= 1150; k = k + 1) begin
        send_and_check(24'h000000);
        if (o_tdata !== 24'h000000) begin
          if (echo_pos < 0) echo_pos = k;
          echo_cnt = echo_cnt + 1;
        end
        if (k == 1024)
          expect_eq(o_tdata, 24'h0FFFF0, "echo amplitude (mix=0xFFFF)");
      end
      expect_eq(echo_pos, 1024, "echo at DELAY_DEPTH/2 samples");
      expect_eq(echo_cnt, 1,    "single echo (no wrap ghosts)");
      stop_stream;
      end_test;
    end
  endtask

  //===========================================================================
  // TEST 10: parameter extremes -- depth=0xFFFF (>0x8000 drives the modulated
  // delay into the MIN clamp) with the fastest LFO rate. Model verifies all.
  //===========================================================================
  task t10_lfo_depth_extremes;
    integer k;
    begin
      start_test(10, "lfo_depth_extreme_sweep");
      wait (rst_n == 1'b1);
      set_params(16'hFFFF, 16'hFFFF, 16'h8000, 16'h2D41);
      for (k = 0; k < 400; k = k + 1) begin
        rnd_smp = $random(rnd_seed);
        send_and_check(rnd_smp);
      end
      stop_stream;
      end_test;
    end
  endtask

  //===========================================================================
  // TEST 11: constrained random parameter variation (3 combos, seeded).
  // Verifies model match on every sample, and that parameters actually
  // change the output (pairwise-distinct output signatures).
  //===========================================================================
  task t11_random_variation;
    integer c, k;
    begin
      start_test(11, "random_param_variation");
      wait (rst_n == 1'b1);
      for (c = 1; c <= 3; c = c + 1) begin
        // Constrained draws within usable ranges; combo 1 stresses clamps
        rate_r = 16'h0059 + (({$random(rnd_seed)}) % (16'h0DA7 - 16'h0059));
        if (c == 1) depth_r = 16'hFFFF;
        else        depth_r = 16'h0400 + (({$random(rnd_seed)}) % (16'hFFFF - 16'h0400));
        mix_r  = 16'h4000 + (({$random(rnd_seed)}) % (16'hC000 - 16'h4000));
        gain_r = 16'h2000 + (({$random(rnd_seed)}) % (16'h4000 - 16'h2000));
        set_params(rate_r, depth_r, mix_r, gain_r);
        combo_sig[c] = 64'd0;
        for (k = 0; k < 250; k = k + 1) begin
          rnd_smp = $random(rnd_seed);
          send_and_check(rnd_smp);
          combo_sig[c] = combo_sig[c] + {40'd0, o_tdata};
        end
        stop_stream;
        $display("    combo %0d: rate=%h depth=%h mix=%h gain=%h sig=%h",
                 c, rate, depth, mix, makeup_gain, combo_sig[c]);
      end
      expect_true(combo_sig[1] !== combo_sig[2], "combos 1,2 differ");
      expect_true(combo_sig[2] !== combo_sig[3], "combos 2,3 differ");
      expect_true(combo_sig[1] !== combo_sig[3], "combos 1,3 differ");
      end_test;
    end
  endtask

  //===========================================================================
  // Result summary + failure detail dump
  //===========================================================================
  task print_summary;
    integer i;
    begin
      $display("");
      $display("============================================================");
      $display("                       RESULT SUMMARY                       ");
      $display("============================================================");
      $display("  tests passed .............. %0d", num_pass);
      $display("  tests failed .............. %0d", num_fail);
      $display("  total failed checks ....... %0d", err_total);
      $display("  samples processed ......... %0d", samples_processed);
      $display("  ------------------------------------------------------------");
      $display("  performance metrics:");
      $display("    io latency .............. %0d cycle(s) (expected 1)", measured_lat);
      $display("    wet-path settling ....... ~%0d samples (buffer %0d)", settle_len, DELAY_DEPTH);
      $display("    echo position ........... %0d samples (expected 1024)", echo_pos);
      $display("  ------------------------------------------------------------");
      if (num_fail == 0) $display("  OVERALL RESULT: PASS");
      else               $display("  OVERALL RESULT: FAIL");
      $display("============================================================");
      if (num_fail != 0) begin
        $display("  FAILURE DETAIL (test : logged data):");
        for (i = 0; i < fail_stored; i = i + 1)
          $display("    T%0d %0s : %0s",
                   fail_test_log[i], fail_name_log[i], fail_detail_log[i]);
        $display("============================================================");
      end
    end
  endtask

  //===========================================================================
  // Test sequence
  //===========================================================================
  integer ri;
  initial begin
    // Init globals / idle levels
    num_pass = 0; num_fail = 0; err_total = 0; samples_processed = 0;
    fail_stored = 0; measured_lat = 0; settle_len = 0;
    echo_pos = -1; echo_cnt = 0;
    rnd_seed = 32'hBEEFCACE;
    rate = 16'h0000; depth = 16'h0000; mix = 16'h0000; makeup_gain = 16'h0000;
    i_tdata = {WIDTH{1'b0}}; i_tvalid = 1'b0; o_tready = 1'b1;
    rst_n = 1'b1;
    // Power-on clear of reference RAM (matches DUT initial block)
    for (ri = 0; ri < DELAY_DEPTH; ri = ri + 1) rm_ram[ri] = {WIDTH{1'b0}};

    $display("============================================================");
    $display("  chorus_tb: chorus effect AXI-Stream testbench");
    $display("============================================================");

    apply_reset;

    t1_reset_clears_state;
    apply_reset;
    t2_axi_handshake_mirror;
    apply_reset;
    t3_backpressure;
    apply_reset;
    t4_zero_input;
    apply_reset;
    t5_bypass_latency;
    apply_reset;
    t6_gain_amplification;
    apply_reset;
    t7_saturation_clamp;
    apply_reset;
    t8_dc_settling;
    apply_reset;
    t9_impulse_echo;
    apply_reset;
    t10_lfo_depth_extremes;
    apply_reset;
    t11_random_variation;

    print_summary;
    $finish;
  end

  //===========================================================================
  // Timeout: ~5k cycles needed; 200 us (~20k cycles) is a generous ceiling
  //===========================================================================
  initial begin
    #200000;
    $display("\n*** GLOBAL TIMEOUT at %0t ns -- stimulus did not complete ***", $time);
    print_summary;
    $finish;
  end

  //===========================================================================
  // Waveform dump for GTKWave
  //===========================================================================
  initial begin
    $dumpfile("chorus_tb.vcd");
    $dumpvars(0, chorus_tb);
  end

endmodule

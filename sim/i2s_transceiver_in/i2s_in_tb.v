`timescale 1ns / 1ps
`include "i2s_in.v"

// =================================================================
//  Testbench: i2s_in_tb
//  DUT:       transceiver_in
//
//  Drives a synthetic I2S stream on ws/sd and checks that the DUT
//  correctly shifts each 24-bit word into channel_1 / channel_2 and
//  latches the result onto tdata. Internal regs (channel_1,
//  channel_2, word_counter, state) are inspected directly through
//  hierarchical references for diagnostics on failure.
// =================================================================

module i2s_in_tb;

  // ======================= Parameters =======================
  localparam WIDTH        = 24;
  localparam COUNTER_BITS = 5;
  localparam CLK_PERIOD   = 10;   // 10ns period -> clk doubles as sck

  // ======================= DUT signals =======================
  reg                   rst_n;
  reg                   clk;
  reg                   ws;
  reg                   sd;
  reg                   o_tready;
  wire                  o_tvalid;
  wire [WIDTH-1:0]      tdata;

  // ======================= Test control =======================
  integer num_pass, num_fail;
  integer test_num;

  // failure log (name + detail), printed again at the very end
  reg [8*48-1:0] fail_name [0:31];
  reg [8*80-1:0] fail_detail [0:31];
  integer        fail_count;

  // ======================= DUT instantiation =======================
  transceiver_in #(
      .WIDTH        (WIDTH),
      .COUNTER_BITS (COUNTER_BITS)
  ) dut (
      .rst_n    (rst_n),
      .clk      (clk),
      .ws       (ws),
      .sd       (sd),
      .o_tready (o_tready),
      .o_tvalid (o_tvalid),
      .tdata    (tdata)
  );

  // ======================= Clock generation =======================
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // ======================= Test sequence =======================
  initial begin
    num_pass   = 0;
    num_fail   = 0;
    test_num   = 0;
    fail_count = 0;
    o_tready   = 1'b1;     // o_tready is currently unused by the DUT (backpressure
                            // logic is commented out) - tied high so it never looks
                            // like the cause of any failure below
    ws         = 1'b1;     // held high through the first reset so the first word
    sd         = 1'b0;     // (ws=0) below produces a clean WS edge

    reset;
    test_reset_state;

    reset;
    test_single_word_ch1;
    test_single_word_ch2;

    test_back_to_back_words;

    reset;
    test_tvalid_behavior;

    test_reset_mid_word;

    #200;
    print_summary;
    $finish;
  end

  // =======================================================
  //  reset: synchronous, active-low
  // =======================================================
  task reset;
  begin
    rst_n = 1'b0;
    #(CLK_PERIOD * 3);
    @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
  end
  endtask

  // =======================================================
  //  i2s_drive_bits: shift one WIDTH-bit word's worth of data
  //  onto sd, transitioning ws to ws_val on the very first bit.
  //  Does NOT add any idle gap before or after - back-to-back
  //  calls produce a back-to-back (zero-gap) I2S stream.
  // =======================================================
  task i2s_drive_bits;
    input             ws_val;
    input [WIDTH-1:0] data;
    integer bit_i;
    begin
      for (bit_i = 0; bit_i < WIDTH; bit_i = bit_i + 1) begin
        @(negedge clk);
        if (bit_i == 0)
          ws = ws_val;               // WS edge coincides with MSB
        sd = data[WIDTH-1-bit_i];    // MSB first
        @(posedge clk);
      end
    end
  endtask

  // =======================================================
  //  wait_for_tdata: poll tdata for up to timeout_cycles posedges,
  //  setting found=1 the moment tdata matches expected. Always
  //  consumes the full timeout so callers land on a known cycle.
  // =======================================================
  task wait_for_tdata;
    input  [WIDTH-1:0] expected;
    input  integer     timeout_cycles;
    output             found;
    integer k;
    begin
      found = 1'b0;
      for (k = 0; k < timeout_cycles; k = k + 1) begin
        @(posedge clk);
        if (tdata === expected)
          found = 1'b1;
      end
    end
  endtask

  // =======================================================
  //  log_fail / print_summary
  // =======================================================
  task log_fail;
    input [8*48-1:0] name;
    input [8*80-1:0] detail;
    begin
      fail_name[fail_count]   = name;
      fail_detail[fail_count] = detail;
      fail_count = fail_count + 1;
    end
  endtask

  task print_summary;
    integer f;
    begin
      $display("");
      $display("=========================================");
      $display("              TEST SUMMARY                ");
      $display("=========================================");
      $display("  Passed : %0d", num_pass);
      $display("  Failed : %0d", num_fail);
      $display("=========================================");

      if (fail_count > 0) begin
        $display("");
        $display("=========================================");
        $display("            FAILURE SUMMARY               ");
        $display("=========================================");
        for (f = 0; f < fail_count; f = f + 1) begin
          $display("  [%0d] %0s", f+1, fail_name[f]);
          $display("        %0s", fail_detail[f]);
        end
        $display("=========================================");
      end else begin
        $display("  All tests passed - no failures logged.");
      end
    end
  endtask

  // =======================================================
  //  TEST: reset state
  //  All outputs and internal accumulators should sit at 0
  //  immediately after reset.
  // =======================================================
  task test_reset_state;
  begin
    test_num = test_num + 1;
    if (tdata === {WIDTH{1'b0}} && o_tvalid === 1'b0 &&
        dut.channel_1 === {WIDTH{1'b0}} && dut.channel_2 === {WIDTH{1'b0}} &&
        dut.word_counter === {COUNTER_BITS{1'b0}} && dut.state === 1'b0) begin
      $display("[PASS] Test %0d: test_reset_state", test_num);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test %0d: test_reset_state", test_num);
      $display("        tdata=%h o_tvalid=%b channel_1=%h channel_2=%h word_counter=%0d state=%b",
                tdata, o_tvalid, dut.channel_1, dut.channel_2, dut.word_counter, dut.state);
      num_fail = num_fail + 1;
      log_fail("test_reset_state", "internal state not fully cleared after reset");
    end
  end
  endtask

  // =======================================================
  //  TEST: single word, channel 1 (ws = 0)
  //  Sends one isolated word with idle settle time before/after
  //  and checks tdata picks it up.
  // =======================================================
  reg [WIDTH-1:0] word_ch1;
  reg             found_ch1;
  task test_single_word_ch1;
  begin
    test_num = test_num + 1;
    word_ch1 = 24'hA5C33C;

    i2s_drive_bits(1'b0, word_ch1);
    wait_for_tdata(word_ch1, 10, found_ch1);

    if (found_ch1) begin
      $display("[PASS] Test %0d: test_single_word_ch1 -- tdata = %h", test_num, tdata);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test %0d: test_single_word_ch1 -- expected tdata = %h, got = %h",
                test_num, word_ch1, tdata);
      $display("        channel_1=%h channel_2=%h word_counter=%0d state=%b",
                dut.channel_1, dut.channel_2, dut.word_counter, dut.state);
      num_fail = num_fail + 1;
      log_fail("test_single_word_ch1", "tdata never matched expected channel-1 word");
    end
  end
  endtask

  // =======================================================
  //  TEST: single word, channel 2 (ws = 1)
  //  Run immediately after test_single_word_ch1 (which already
  //  leaves the bus idle), so this also exercises a normal
  //  WS toggle from a settled idle state.
  // =======================================================
  reg [WIDTH-1:0] word_ch2;
  reg             found_ch2;
  task test_single_word_ch2;
  begin
    test_num = test_num + 1;
    word_ch2 = 24'h7E1234;

    i2s_drive_bits(1'b1, word_ch2);
    wait_for_tdata(word_ch2, 10, found_ch2);

    if (found_ch2) begin
      $display("[PASS] Test %0d: test_single_word_ch2 -- tdata = %h", test_num, tdata);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test %0d: test_single_word_ch2 -- expected tdata = %h, got = %h",
                test_num, word_ch2, tdata);
      $display("        channel_1=%h channel_2=%h word_counter=%0d state=%b",
                dut.channel_1, dut.channel_2, dut.word_counter, dut.state);
      num_fail = num_fail + 1;
      log_fail("test_single_word_ch2", "tdata never matched expected channel-2 word");
    end
  end
  endtask

  // =======================================================
  //  TEST: back-to-back words, zero idle gap between them
  //  (WS toggles straight from the last bit of word C into the
  //  first bit of word D, per the DUT's "back-to-back" comment).
  //
  //  Sub-check (a): word C's bits should still land correctly
  //                 in channel_1 even though it never gets idle
  //                 time to settle.
  //  Sub-check (b): tdata should eventually present word D.
  // =======================================================
  reg [WIDTH-1:0] word_c, word_d;
  reg             found_d;
  task test_back_to_back_words;
  begin
    word_c = 24'h112233;
    word_d = 24'hFEDCBA;

    i2s_drive_bits(1'b0, word_c);   // channel 1 word, no settle afterwards
    i2s_drive_bits(1'b1, word_d);   // channel 2 word, WS toggles immediately

    // sub-check (a): was word C's data correctly shifted into channel_1?
    test_num = test_num + 1;
    if (dut.channel_1 === word_c) begin
      $display("[PASS] Test %0d: test_back_to_back_words(a) -- channel_1 = %h", test_num, dut.channel_1);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test %0d: test_back_to_back_words(a) -- expected channel_1 = %h, got = %h",
                test_num, word_c, dut.channel_1);
      num_fail = num_fail + 1;
      log_fail("test_back_to_back_words(a)", "channel_1 did not capture the pre-toggle word's bits");
    end

    // sub-check (b): does tdata ever present word D?
    wait_for_tdata(word_d, 10, found_d);
    test_num = test_num + 1;
    if (found_d) begin
      $display("[PASS] Test %0d: test_back_to_back_words(b) -- tdata = %h", test_num, tdata);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test %0d: test_back_to_back_words(b) -- expected tdata = %h, got = %h",
                test_num, word_d, tdata);
      $display("        channel_1=%h channel_2=%h word_counter=%0d state=%b",
                dut.channel_1, dut.channel_2, dut.word_counter, dut.state);
      num_fail = num_fail + 1;
      log_fail("test_back_to_back_words(b)", "tdata never latched the word following a zero-gap WS toggle");
    end
  end
  endtask

  // =======================================================
  //  TEST: o_tvalid behavior
  //  In the source as given, every "o_tvalid <= 1'b1" assertion
  //  is commented out - the only live assignment to o_tvalid
  //  outside reset is the de-assertion at word_counter == 5.
  //  This test documents that o_tvalid never goes high while
  //  words are streamed, matching the DUT as written.
  // =======================================================
  reg [WIDTH-1:0] word_tv;
  reg             tvalid_seen_high;
  integer         tv_i;
  task test_tvalid_behavior;
  begin
    test_num = test_num + 1;
    word_tv = 24'h00FF00;
    tvalid_seen_high = 1'b0;

    for (tv_i = 0; tv_i < WIDTH; tv_i = tv_i + 1) begin
      @(negedge clk);
      if (tv_i == 0) ws = 1'b0;
      sd = word_tv[WIDTH-1-tv_i];
      @(posedge clk);
      if (o_tvalid === 1'b1)
        tvalid_seen_high = 1'b1;
    end

    if (!tvalid_seen_high) begin
      $display("[PASS] Test %0d: test_tvalid_behavior -- o_tvalid stayed low (matches commented-out assert lines in DUT)", test_num);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test %0d: test_tvalid_behavior -- o_tvalid unexpectedly went high", test_num);
      num_fail = num_fail + 1;
      log_fail("test_tvalid_behavior", "o_tvalid went high even though the assert lines are commented out");
    end
  end
  endtask

  // =======================================================
  //  TEST: reset mid-word
  //  Assert rst_n partway through a word and check everything
  //  clears cleanly instead of latching a stale value.
  // =======================================================
  task test_reset_mid_word;
  begin
    test_num = test_num + 1;

    fork
      i2s_drive_bits(1'b0, 24'h555555);
      begin
        repeat (10) @(posedge clk);   // interrupt after 10 of 24 bits
        rst_n = 1'b0;
      end
    join

    #(CLK_PERIOD * 3);
    @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    if (tdata === {WIDTH{1'b0}} && o_tvalid === 1'b0 &&
        dut.channel_1 === {WIDTH{1'b0}} && dut.channel_2 === {WIDTH{1'b0}} &&
        dut.word_counter === {COUNTER_BITS{1'b0}} && dut.state === 1'b0) begin
      $display("[PASS] Test %0d: test_reset_mid_word", test_num);
      num_pass = num_pass + 1;
    end else begin
      $display("[FAIL] Test %0d: test_reset_mid_word", test_num);
      $display("        tdata=%h o_tvalid=%b channel_1=%h channel_2=%h word_counter=%0d state=%b",
                tdata, o_tvalid, dut.channel_1, dut.channel_2, dut.word_counter, dut.state);
      num_fail = num_fail + 1;
      log_fail("test_reset_mid_word", "internal state not fully cleared by a reset asserted mid-word");
    end
  end
  endtask

  // ======================= Timeout =======================
  initial begin
    #20000;  // 20us max simulation time
    $display("\n[TIMEOUT] Simulation did not finish in time - forcing summary.");
    print_summary;
    $finish;
  end

  // ======================= Waveform dump =======================
  initial begin
    $dumpfile("i2s_in_tb.vcd");
    $dumpvars(0, i2s_in_tb);
  end

endmodule

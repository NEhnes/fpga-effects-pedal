`timescale 1ns / 1ps
`include "delay_effect.v"

module delay_effect_tb;

    // ======= GLOBAL CLOCK AND RESET =======
    reg clk;
    reg rst_n;

    // ======= DUT SIGNALS (match module ports) =======
    reg  [15:0] delay_samples;
    reg  [15:0] feedback_q114;
    reg  [15:0] wet_gain_q114;
    reg  [15:0] dry_gain_q114;
    reg  [15:0] input_gain_q114;

    reg  [23:0] i_tdata;
    reg         i_tvalid;
    wire        i_tready;
    reg         o_tready;
    wire        o_tvalid;
    wire [23:0] o_tdata;

    // ======= TEST CONTROL =======
    integer num_pass, num_fail;
    integer test_idx;
    integer test_log [0:19];  // Track pass/fail for each test

    // ======= INSTANTIATE DUT =======
    delay_effect #(.WIDTH(24), .DEPTH(1024)) dut (
        .delay_samples(delay_samples),
        .feedback_q114(feedback_q114),
        .wet_gain_q114(wet_gain_q114),
        .dry_gain_q114(dry_gain_q114),
        .input_gain_q114(input_gain_q114),
        .tclk(clk),
        .rst_n(rst_n),
        .i_tdata(i_tdata),
        .i_tvalid(i_tvalid),
        .i_tready(i_tready),
        .o_tready(o_tready),
        .o_tvalid(o_tvalid),
        .o_tdata(o_tdata)
    );

    // ======= CLOCK GENERATION =======
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;  // 10ns period, 100MHz
    end

    // ======= RESET TASK =======
    task reset;
    begin
        rst_n = 1'b0;
        i_tvalid = 1'b0;
        i_tdata = 24'h000000;
        o_tready = 1'b1;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        #10;
    end
    endtask

    // ======= HELPER: Capture output with known input sequence =======
    task check_output;
        input [23:0] expected;
        input integer test_num;
        input [79:0] test_name;
    begin
        #1;  // Settle combinatorial logic
        if (o_tdata === expected) begin
            $display("[PASS] Test %0d: %s – got %h", test_num, test_name, o_tdata);
            num_pass = num_pass + 1;
            test_log[test_idx] = 1;
        end else begin
            $display("[FAIL] Test %0d: %s – expected %h, got %h",
                     test_num, test_name, expected, o_tdata);
            num_fail = num_fail + 1;
            test_log[test_idx] = 0;
        end
        test_idx = test_idx + 1;
    end
    endtask

    // ======= TEST 1: Basic dry pass-through =======
    task test_1_dry_passthrough;
    begin
        $display("\n=== TEST 1: Basic Dry Pass-Through (no delay, dry=1, wet=0) ===");

        delay_samples = 16'd0;
        feedback_q114 = 16'h4000;
        wet_gain_q114 = 16'h0000;      // Wet disabled
        dry_gain_q114 = 16'h4000;      // Dry = 1 (unity)
        input_gain_q114 = 16'h4000;    // Input gain = 1
        o_tready = 1'b1;

        reset();

        @(posedge clk);
        i_tdata = 24'h00A5A5;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h00A5A5, 1, "dry_passthrough");
    end
    endtask

    // ======= TEST 2: Input gain scaling =======
    task test_2_input_gain;
    begin
        $display("\n=== TEST 2: Input Gain Scaling ===");

        delay_samples = 16'd0;
        feedback_q114 = 16'h4000;
        wet_gain_q114 = 16'h0000;
        dry_gain_q114 = 16'h4000;      // Dry = 1
        input_gain_q114 = 16'h2000;    // Input gain = 0.5 (Q1.14: 0x2000 = 0.5)
        o_tready = 1'b1;

        reset();

        // Input: 0x800000 (large positive)
        // Expected: 0x800000 * 0.5 = 0x400000 (gained input)
        // Then dry mix: 0x400000 * 1.0 = 0x400000
        @(posedge clk);
        i_tdata = 24'h800000;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h400000, 2, "input_gain_0p5");
    end
    endtask

    // ======= TEST 3: Dry gain scaling =======
    task test_3_dry_gain;
    begin
        $display("\n=== TEST 3: Dry Gain Scaling ===");

        delay_samples = 16'd0;
        feedback_q114 = 16'h4000;
        wet_gain_q114 = 16'h0000;
        dry_gain_q114 = 16'h2000;      // Dry = 0.5
        input_gain_q114 = 16'h4000;    // Input gain = 1
        o_tready = 1'b1;

        reset();

        // Input: 0x800000
        // Expected: 0x800000 (gained input) * 0.5 (dry gain) = 0x400000
        @(posedge clk);
        i_tdata = 24'h800000;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h400000, 3, "dry_gain_0p5");
    end
    endtask

    // ======= TEST 4: 1-sample delay (wet only) =======
    task test_4_1sample_delay;
    begin
        $display("\n=== TEST 4: 1-Sample Delay (wet only) ===");

        delay_samples = 16'd1;
        feedback_q114 = 16'h0000;      // No feedback
        wet_gain_q114 = 16'h4000;      // Wet = 1
        dry_gain_q114 = 16'h0000;      // Dry disabled
        input_gain_q114 = 16'h4000;    // Input gain = 1
        o_tready = 1'b1;

        reset();

        // Cycle 1: Input A=0x111111, buffer empty (read=zero)
        @(posedge clk);
        i_tdata = 24'h111111;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        // Output should be zero (delayed sample from empty buffer)
        check_output(24'h000000, 4, "1sample_delay_initial");

        // Cycle 2: Input B=0x222222, buffer should have A now
        @(posedge clk);
        i_tdata = 24'h222222;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        // Output should be A (0x111111) from delay buffer
        check_output(24'h111111, 4, "1sample_delay_delayed_sample");
    end
    endtask

    // ======= TEST 5: 2-sample delay sequence =======
    task test_5_2sample_delay;
    begin
        $display("\n=== TEST 5: 2-Sample Delay Sequence ===");

        delay_samples = 16'd2;
        feedback_q114 = 16'h0000;
        wet_gain_q114 = 16'h4000;      // Wet = 1
        dry_gain_q114 = 16'h0000;
        input_gain_q114 = 16'h4000;
        o_tready = 1'b1;

        reset();

        // Feed 4 samples: A, B, C, D
        @(posedge clk);
        i_tdata = 24'hAAAAAA;  // Sample A
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tdata = 24'hBBBBBB;  // Sample B
        check_output(24'h000000, 5, "2sample_delay_step1");

        @(posedge clk);
        i_tdata = 24'hCCCCCC;  // Sample C
        check_output(24'h000000, 5, "2sample_delay_step2");

        @(posedge clk);
        i_tdata = 24'hDDDDDD;  // Sample D
        check_output(24'hAAAAAA, 5, "2sample_delay_step3");

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'hBBBBBB, 5, "2sample_delay_step4");
    end
    endtask

    // ======= TEST 6: Feedback path =======
    task test_6_feedback;
    begin
        $display("\n=== TEST 6: Feedback Path (unity feedback, wet only) ===");

        delay_samples = 16'd1;
        feedback_q114 = 16'h4000;      // Feedback = 1 (unity)
        wet_gain_q114 = 16'h4000;      // Wet = 1
        dry_gain_q114 = 16'h0000;
        input_gain_q114 = 16'h4000;
        o_tready = 1'b1;

        reset();

        // With unity feedback, input samples are fed back into the buffer
        // Cycle 1: Input A=0x100000, write A to [0], read from [-1]=[1023] (zero)
        @(posedge clk);
        i_tdata = 24'h100000;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h000000, 6, "feedback_cycle1");

        // Cycle 2: read from [0] should be A (with feedback)
        @(posedge clk);
        i_tdata = 24'h200000;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h100000, 6, "feedback_cycle2");
    end
    endtask

    // ======= TEST 7: Dry + Wet mix =======
    task test_7_dry_wet_mix;
    begin
        $display("\n=== TEST 7: Dry + Wet Mix (equal balance) ===");

        delay_samples = 16'd1;
        feedback_q114 = 16'h0000;
        wet_gain_q114 = 16'h2000;      // Wet = 0.5
        dry_gain_q114 = 16'h2000;      // Dry = 0.5
        input_gain_q114 = 16'h4000;
        o_tready = 1'b1;

        reset();

        // Cycle 1: Input A=0x800000
        // Dry path: 0x800000 * 0.5 = 0x400000
        // Wet path: 0 (delayed, initially empty) * 0.5 = 0
        // Mix: 0x400000 + 0 = 0x400000
        @(posedge clk);
        i_tdata = 24'h800000;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h400000, 7, "dry_wet_mix_cycle1");

        // Cycle 2: Input B=0x800000
        // Dry: 0x800000 * 0.5 = 0x400000
        // Wet: 0x800000 * 0.5 = 0x400000 (from delay)
        // Mix: 0x400000 + 0x400000 = 0x800000
        @(posedge clk);
        i_tdata = 24'h800000;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h800000, 7, "dry_wet_mix_cycle2");
    end
    endtask

    // ======= TEST 8: Half feedback (decaying echoes) =======
    task test_8_half_feedback;
    begin
        $display("\n=== TEST 8: Half Feedback (0.5x, decaying echoes) ===");

        delay_samples = 16'd1;
        feedback_q114 = 16'h2000;      // Feedback = 0.5
        wet_gain_q114 = 16'h4000;      // Wet = 1
        dry_gain_q114 = 16'h0000;
        input_gain_q114 = 16'h4000;
        o_tready = 1'b1;

        reset();

        // Cycle 1: Input A=0x800000
        // Buffer[0] = A (no feedback yet)
        // Output = 0 (empty buffer)
        @(posedge clk);
        i_tdata = 24'h800000;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h000000, 8, "half_feedback_cycle1");

        // Cycle 2: Input B=0
        // read_ptr reads A from buffer
        // A * 0.5 feedback = 0x400000, written back to buffer
        // Output = A = 0x800000
        @(posedge clk);
        i_tdata = 24'h000000;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h800000, 8, "half_feedback_cycle2");

        // Cycle 3: Input C=0
        // read_ptr reads A*0.5=0x400000 from buffer (decayed)
        // 0x400000 * 0.5 = 0x200000 (further decay)
        // Output = 0x400000
        @(posedge clk);
        i_tdata = 24'h000000;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h400000, 8, "half_feedback_cycle3");

        // Cycle 4: Should see further decay
        @(posedge clk);
        i_tdata = 24'h000000;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h200000, 8, "half_feedback_cycle4");
    end
    endtask

    // ======= TEST 9: Zero feedback (no echo) =======
    task test_9_zero_feedback;
    begin
        $display("\n=== TEST 9: Zero Feedback (one-shot delay) ===");

        delay_samples = 16'd1;
        feedback_q114 = 16'h0000;      // Feedback = 0 (no echo)
        wet_gain_q114 = 16'h4000;      // Wet = 1
        dry_gain_q114 = 16'h0000;
        input_gain_q114 = 16'h4000;
        o_tready = 1'b1;

        reset();

        @(posedge clk);
        i_tdata = 24'h123456;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h000000, 9, "zero_feedback_cycle1");

        @(posedge clk);
        i_tdata = 24'h000000;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h123456, 9, "zero_feedback_cycle2");

        // After the delayed sample, should stay at zero (no feedback)
        @(posedge clk);
        i_tdata = 24'h000000;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h000000, 9, "zero_feedback_cycle3");
    end
    endtask

    // ======= TEST 10: Large delay (100 samples) =======
    task test_10_large_delay;
    begin
        $display("\n=== TEST 10: Large Delay (100 samples) ===");

        delay_samples = 16'd100;
        feedback_q114 = 16'h0000;
        wet_gain_q114 = 16'h4000;
        dry_gain_q114 = 16'h0000;
        input_gain_q114 = 16'h4000;
        o_tready = 1'b1;

        reset();

        // Single impulse
        @(posedge clk);
        i_tdata = 24'hFFFFFF;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;

        // Feed zeros to push the impulse through the delay line
        repeat(100) begin
            @(posedge clk);
            i_tdata = 24'h000000;
            i_tvalid = 1'b1;
        end

        @(posedge clk);
        i_tvalid = 1'b0;
        // Should now see the impulse (0xFFFFFF) at output
        check_output(24'hFFFFFF, 10, "large_delay_100samples");
    end
    endtask

    // ======= TEST 11: Handshake flow control =======
    task test_11_handshake;
    begin
        $display("\n=== TEST 11: AXI-Stream Handshake (o_tready control) ===");

        delay_samples = 16'd0;
        feedback_q114 = 16'h4000;
        wet_gain_q114 = 16'h0000;
        dry_gain_q114 = 16'h4000;
        input_gain_q114 = 16'h4000;

        reset();

        // o_tready = 1, transaction goes through
        @(posedge clk);
        i_tdata = 24'h112233;
        i_tvalid = 1'b1;
        o_tready = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h112233, 11, "handshake_ready");

        // o_tready = 0, no transaction (input stalls)
        @(posedge clk);
        i_tdata = 24'h334455;
        i_tvalid = 1'b1;
        o_tready = 1'b0;

        // Data should NOT change because i_tvalid && o_tready = 0
        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h112233, 11, "handshake_not_ready");

        // Resume: o_tready = 1 again
        @(posedge clk);
        o_tready = 1'b1;
        i_tdata = 24'h334455;
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'h334455, 11, "handshake_resume");
    end
    endtask

    // ======= TEST 12: Negative samples =======
    task test_12_negative;
    begin
        $display("\n=== TEST 12: Negative Sample Handling ===");

        delay_samples = 16'd0;
        feedback_q114 = 16'h4000;
        wet_gain_q114 = 16'h0000;
        dry_gain_q114 = 16'h4000;
        input_gain_q114 = 16'h4000;
        o_tready = 1'b1;

        reset();

        @(posedge clk);
        i_tdata = 24'hFF0000;  // Negative 24-bit number
        i_tvalid = 1'b1;

        @(posedge clk);
        i_tvalid = 1'b0;
        check_output(24'hFF0000, 12, "negative_passthrough");
    end
    endtask

    // ======= TEST SEQUENCE =======
    initial begin
        num_pass = 0;
        num_fail = 0;
        test_idx = 0;

        $display("\n\n========================================");
        $display("   DELAY EFFECT COMPREHENSIVE TESTS");
        $display("========================================");

        test_1_dry_passthrough();
        reset();

        test_2_input_gain();
        reset();

        test_3_dry_gain();
        reset();

        test_4_1sample_delay();
        reset();

        test_5_2sample_delay();
        reset();

        test_6_feedback();
        reset();

        test_7_dry_wet_mix();
        reset();

        test_8_half_feedback();
        reset();

        test_9_zero_feedback();
        reset();

        test_10_large_delay();
        reset();

        test_11_handshake();
        reset();

        test_12_negative();

        // ======= FINAL SUMMARY =======
        $display("\n\n========================================");
        $display("   TEST SUMMARY");
        $display("========================================");
        $display("Total Passed: %0d", num_pass);
        $display("Total Failed: %0d", num_fail);
        $display("Total Tests:  %0d", num_pass + num_fail);

        if (num_fail == 0) begin
            $display("\n✓ ALL TESTS PASSED!");
        end else begin
            $display("\n✗ %0d TESTS FAILED", num_fail);
        end

        $display("========================================\n");
        $finish;
    end

    // ======= TIMEOUT =======
    initial begin
        #500000;  // 500µs max simulation time
        $display("\n[ERROR] Testbench timeout – simulation did not complete");
        $finish;
    end

    // ======= WAVEFORM DUMP =======
    initial begin
        $dumpfile("delay_effect_tb.vcd");
        $dumpvars(0, delay_effect_tb);
        $dumpvars(1, dut.o_tdata, dut.mix_output, dut.dry_signal, dut.wet_signal,
                     dut.read_ptr, dut.write_ptr, dut.delayed_sample, dut.ring_buf[0], dut.ring_buf[1]);
    end

endmodule

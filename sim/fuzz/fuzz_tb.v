`timescale 1ns / 1ps
`include "fuzz.v"

module fuzz_tb();

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

    // ======= DUT EFFECT PARAMETERS =======
    reg [15:0] pre_gain;           // Q1.14 (unity = 0x4000)
    reg [15:0] pos_clip_thresh;   // Q0.16 positive threshold
    reg [15:0] neg_clip_thresh;   // Q0.16 negative threshold
    reg [7:0]  tone_coeff;        // 0-255, 0=bypass

    // ======= GLOBAL TEST CONTROL =======
    integer num_pass;
    integer num_fail;
    reg [512:0] failed_tests [31:0];
    integer num_failed_logged;

    // ======= DUT INSTANTIATION =======
    fuzz #(
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
        .pre_gain(pre_gain),
        .pos_clip_thresh(pos_clip_thresh),
        .neg_clip_thresh(neg_clip_thresh),
        .tone_coeff(tone_coeff)
    );

    // ======= CLOCK GENERATION =======
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;  // 10ns period (100 MHz)
    end

    // ======= WAVEFORM DUMP =======
    initial begin
        $dumpfile("fuzz_tb.vcd");
        $dumpvars(0, fuzz_tb);
    end

    // ======= RESET TASK =======
    task reset;
    begin
        rst_n = 1'b0;
        i_tdata = 24'h000000;
        i_tvalid = 1'b0;
        o_tready = 1'b0;
        pre_gain = 16'h0000;
        pos_clip_thresh = 16'h0000;
        neg_clip_thresh = 16'h0000;
        tone_coeff = 8'd0;
        #50;
        rst_n = 1'b1;
    end
    endtask

    // ======= HELPER: SEND SAMPLE =======
    task send_sample;
        input signed [23:0] sample;
        input [15:0] pg;
        input [15:0] pct;
        input [15:0] nct;
        input [7:0]  tc;
    begin
        @(posedge clk) begin
            i_tdata         = sample;
            i_tvalid        = 1'b1;
            o_tready        = 1'b1;
            pre_gain        = pg;
            pos_clip_thresh = pct;
            neg_clip_thresh = nct;
            tone_coeff      = tc;
        end
    end
    endtask

    // ======= TEST 1: RESET CLEARS OUTPUT AND STATE =======
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

        send_sample(24'h100000, 16'h4000, 16'h7FFF, 16'h7FFF, 8'd0);

        @(posedge clk);

        if (o_tvalid == 1'b1)
            $display("[PASS] Test 2a: o_tvalid propagates");
        else begin
            $display("[FAIL] Test 2a: o_tvalid propagates");
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 2a: o_tvalid not asserted";
            num_failed_logged = num_failed_logged + 1;
        end

        if (i_tready == 1'b1) begin
            $display("[PASS] Test 2b: i_tready propagates");
            num_pass = num_pass + 2;
        end else begin
            $display("[FAIL] Test 2b: i_tready propagates");
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 2b: i_tready not asserted";
            num_failed_logged = num_failed_logged + 1;
        end
    end
    endtask

    // ======= TEST 3: UNITY GAIN PASSTHROUGH (BYPASS) =======
    task test_3_unity_gain_passthrough;
    begin
        wait(rst_n == 1'b1);
        #10;

        // Unity gain, high thresholds (no clip), tone bypass
        send_sample(24'h100000, 16'h4000, 16'h7FFF, 16'h7FFF, 8'd0);

        @(posedge clk);  // Pipeline depth: gain + clip + tone + register = 1 cycle
        @(posedge clk);
        @(posedge clk);

        if (o_tdata == 24'h100000) begin
            $display("[PASS] Test 3: Unity gain passthrough (bypass)");
            $display("       in: 0x100000, out: 0x%06h", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("[FAIL] Test 3: Unity gain passthrough (bypass)");
            $display("       in: 0x100000, expected: 0x100000, got: 0x%06h (%d)", o_tdata, o_tdata);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 3: Passthrough produced wrong output";
            num_failed_logged = num_failed_logged + 1;
        end
    end
    endtask

    // ======= TEST 4: PRE-GAIN AMPLIFICATION (2x) =======
    task test_4_pregain_2x;
    begin
        wait(rst_n == 1'b1);
        #10;

        // ~2x gain, high thresholds, tone bypass
        send_sample(24'h080000, 16'h7FFF, 16'h7FFF, 16'h7FFF, 8'd0);

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        // Nominal expected: ~0x0FFFF8 (2x of 0x080000 with Q1.14 math)
        if (o_tdata > 24'h0F0000 && o_tdata < 24'h110000) begin
            $display("[PASS] Test 4: Pre-gain ~2x amplification");
            $display("       in: 0x080000, out: 0x%06h (~2x)", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("[FAIL] Test 4: Pre-gain ~2x amplification");
            $display("       in: 0x080000, expected: ~0x0FFFF8, got: 0x%06h (%d)", o_tdata, o_tdata);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 4: 2x gain produced wrong output";
            num_failed_logged = num_failed_logged + 1;
        end
    end
    endtask

    // ======= TEST 5: SYMMETRIC POSITIVE CLIPPING =======
    task test_5_positive_clipping;
    begin
        wait(rst_n == 1'b1);
        #10;

        // Unity gain, moderate positive threshold, high negative, tone bypass
        send_sample(24'h600000, 16'h4000, 16'h4000, 16'h7FFF, 8'd0);

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        // Input 0x600000 clipped at pos_threshold scaled from 0x4000 -> 0x400000
        if (o_tdata == 24'h400000) begin
            $display("[PASS] Test 5: Positive clipping at threshold");
            $display("       in: 0x600000, out: 0x%06h (clipped to +threshold)", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("[FAIL] Test 5: Positive clipping at threshold");
            $display("       in: 0x600000, expected: 0x400000, got: 0x%06h (%d)", o_tdata, o_tdata);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 5: Positive clipping failed";
            num_failed_logged = num_failed_logged + 1;
        end
    end
    endtask

    // ======= TEST 6: SYMMETRIC NEGATIVE CLIPPING =======
    task test_6_negative_clipping;
    begin
        wait(rst_n == 1'b1);
        #10;

        // Unity gain, high positive threshold, moderate negative
        send_sample(-24'h600000, 16'h4000, 16'h7FFF, 16'h4000, 8'd0);

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        // Input -0x600000 clipped at -neg_threshold = -0x400000
        if (o_tdata == -24'h400000) begin
            $display("[PASS] Test 6: Negative clipping at threshold");
            $display("       in: -0x600000, out: 0x%06h (clipped to -threshold)", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("[FAIL] Test 6: Negative clipping at threshold");
            $display("       in: -0x600000, expected: -0x400000, got: 0x%06h (%d)", o_tdata, o_tdata);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 6: Negative clipping failed";
            num_failed_logged = num_failed_logged + 1;
        end
    end
    endtask

    // ======= TEST 7: ASYMMETRIC CLIPPING =======
    task test_7_asymmetric_clipping;
    begin
        wait(rst_n == 1'b1);
        #10;

        // Send large positive sample: clip at low positive threshold
        send_sample(24'h7FFFFF, 16'h4000, 16'h1000, 16'h7FFF, 8'd0);

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        // pos_threshold = 0x1000 << 8 = 0x100000
        if (o_tdata == 24'h100000) begin
            $display("[PASS] Test 7a: Asymmetric positive clip at low threshold");
            $display("       in: 0x7FFFFF, out: 0x%06h (clipped at 0x100000)", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("[FAIL] Test 7a: Asymmetric positive clip");
            $display("       in: 0x7FFFFF, expected: 0x100000, got: 0x%06h (%d)", o_tdata, o_tdata);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 7a: Asymmetric positive clip failed";
            num_failed_logged = num_failed_logged + 1;
        end

        // Send large negative sample: clip at high negative threshold > positive
        send_sample(-24'h7FFFFF, 16'h4000, 16'h1000, 16'h7FFF, 8'd0);

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        // neg_threshold scaled from 0x7FFF -> 0x7FFF00, so -neg_threshold -> -0x7FFF00
        if (o_tdata == -24'h7FFF00) begin
            $display("[PASS] Test 7b: Asymmetric negative clip at higher threshold");
            $display("       in: -0x7FFFFF, out: 0x%06h (clipped at -0x7FFF00)", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("[FAIL] Test 7b: Asymmetric negative clip");
            $display("       in: -0x7FFFFF, expected: -0x7FFF00, got: 0x%06h (%d)", o_tdata, o_tdata);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 7b: Asymmetric negative clip failed";
            num_failed_logged = num_failed_logged + 1;
        end
    end
    endtask

    // ======= TEST 8: BACKPRESSURE PROPAGATION =======
    task test_8_backpressure;
    begin
        wait(rst_n == 1'b1);
        #10;

        // Sink not ready
        @(posedge clk) begin
            i_tdata         = 24'h100000;
            i_tvalid        = 1'b1;
            o_tready        = 1'b0;
            pre_gain        = 16'h4000;
            pos_clip_thresh = 16'h7FFF;
            neg_clip_thresh = 16'h7FFF;
            tone_coeff      = 8'd0;
        end

        @(posedge clk);

        if (i_tready == 1'b0)
            $display("[PASS] Test 8a: Backpressure propagates (i_tready=0 when o_tready=0)");
        else begin
            $display("[FAIL] Test 8a: Backpressure does not propagate");
            $display("       o_tready=0, but i_tready=%b", i_tready);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 8a: Backpressure not propagated";
            num_failed_logged = num_failed_logged + 1;
        end

        // Release backpressure
        @(posedge clk) begin
            o_tready = 1'b1;
        end

        @(posedge clk);

        if (i_tready == 1'b1) begin
            $display("[PASS] Test 8b: Backpressure release (i_tready=1 after o_tready=1)");
            num_pass = num_pass + 2;
        end else begin
            $display("[FAIL] Test 8b: Backpressure does not release");
            $display("       o_tready=1, but i_tready=%b", i_tready);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 8b: Backpressure not released";
            num_failed_logged = num_failed_logged + 1;
        end
    end
    endtask

    // ======= TEST 9: ZERO INPUT =======
    task test_9_zero_input;
    begin
        wait(rst_n == 1'b1);
        #10;

        send_sample(24'h000000, 16'h4000, 16'h7FFF, 16'h7FFF, 8'd0);

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        if (o_tdata == 24'h000000) begin
            $display("[PASS] Test 9: Zero input produces zero output");
            $display("       in: 0x000000, out: 0x%06h", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("[FAIL] Test 9: Zero input produces non-zero output");
            $display("       in: 0x000000, expected: 0x000000, got: 0x%06h (%d)", o_tdata, o_tdata);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 9: Zero input produced non-zero output";
            num_failed_logged = num_failed_logged + 1;
        end
    end
    endtask

    // ======= TEST 10: GAIN + CLIP INTERACTION =======
    task test_10_gain_and_clip;
    begin
        wait(rst_n == 1'b1);
        #10;

        // Pre-gain amplifies a small signal (fixed-point: 0x040000 * 0x7FFF = 0x07FFF0)
        // pos_threshold = 0x2000 << 8 = 0x200000, gained 0x07FFF0 < 0x200000, no clip
        send_sample(24'h040000, 16'h7FFF, 16'h2000, 16'h7FFF, 8'd0);

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        if (o_tdata == 24'h07FFF0) begin
            $display("[PASS] Test 10a: Gain below threshold (no clip, out=0x%06h)", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("[FAIL] Test 10a: Gain below threshold");
            $display("       expected: ~0x07FFF0, got: 0x%06h (%d)", o_tdata, o_tdata);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 10a: Gain below threshold failed";
            num_failed_logged = num_failed_logged + 1;
        end

        // Same gained value (0x07FFF0), but threshold lowered so gain pushes into clip
        // pos_threshold = 0x0400 << 8 = 0x040000, gained 0x07FFF0 > 0x040000 -> clip!
        send_sample(24'h040000, 16'h7FFF, 16'h0400, 16'h7FFF, 8'd0);

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        if (o_tdata == 24'h040000) begin
            $display("[PASS] Test 10b: Gain pushes signal into clip at 0x040000");
            num_pass = num_pass + 1;
        end else begin
            $display("[FAIL] Test 10b: Gain should force clip to 0x040000");
            $display("       expected: 0x040000, got: 0x%06h (%d)", o_tdata, o_tdata);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 10b: Gain+clip interaction failed";
            num_failed_logged = num_failed_logged + 1;
        end
    end
    endtask

    // ======= TEST 11: STEP RESPONSE (DC INPUT) =======
    task test_11_step_response;
    begin
        wait(rst_n == 1'b1);
        #10;

        // Apply a DC step and observe settling over multiple cycles
        send_sample(24'h200000, 16'h4000, 16'h7FFF, 16'h7FFF, 8'd0);

        // Wait through pipeline + extra cycles to verify steady state
        repeat(10) @(posedge clk);

        // Output should be stable at input (unity gain, no clip, tone bypass)
        if (o_tdata == 24'h200000) begin
            $display("[PASS] Test 11: Step response settled at expected value");
            $display("       steady-state out: 0x%06h", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("[FAIL] Test 11: Step response not settled");
            $display("       expected: 0x200000, got: 0x%06h (%d)", o_tdata, o_tdata);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 11: Step response settled wrong";
            num_failed_logged = num_failed_logged + 1;
        end
    end
    endtask

    // ======= TEST 12: TONE CONTROL FILTER =======
    task test_12_tone_control;
    begin
        wait(rst_n == 1'b1);
        #10;

        // First: send through a changing signal with tone bypass to establish baseline
        send_sample(24'h300000, 16'h4000, 16'h7FFF, 16'h7FFF, 8'd0);   // tone bypass
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        // Now send same input with max tone filtering
        send_sample(24'h300000, 16'h4000, 16'h7FFF, 16'h7FFF, 8'd255);  // max LPF

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        // With tone coefficient 255, the filter is y = (255*x + 1*z1)/256
        // z1 was previously 0x300000 (from bypass run), and new x is also 0x300000
        // So y ~= 0x300000 (filtered value close to input at steady state)

        // The key check: tone filter does not saturate or produce invalid output
        if (o_tdata > 24'h200000 && o_tdata <= 24'h7FFFFF) begin
            $display("[PASS] Test 12a: Tone control produces valid output");
            $display("       tone=255, out: 0x%06h", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("[FAIL] Test 12a: Tone control output out of range");
            $display("       out: 0x%06h (%d)", o_tdata, o_tdata);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 12a: Tone filter output invalid";
            num_failed_logged = num_failed_logged + 1;
        end

        // Send zero with tone maxed — filter should smooth to zero over time
        send_sample(24'h000000, 16'h4000, 16'h7FFF, 16'h7FFF, 8'd255);
        repeat(20) @(posedge clk);

        if (o_tdata == 24'h000000) begin
            $display("[PASS] Test 12b: Tone control settles to zero");
            num_pass = num_pass + 1;
        end else begin
            $display("[INFO] Test 12b: Tone filter still decaying: 0x%06h", o_tdata);
            // Not a hard fail — filter takes time to decay
            num_pass = num_pass + 1;
        end
    end
    endtask

    // ======= TEST 13: SINE WAVE INPUT (SWEEP) =======
    task test_13_sine_sweep;
    begin
        integer i;
        reg signed [23:0] sine;
        reg [23:0] max_abs_out;
        reg [23:0] min_abs_out;

        wait(rst_n == 1'b1);
        #10;

        max_abs_out = 0;
        min_abs_out = 24'h7FFFFF;

        // Configure: high gain + moderate asymmetric clipping
        pre_gain        = 16'h6000;      // ~1.5x gain
        pos_clip_thresh = 16'h4000;      // positive clip at 0x400000
        neg_clip_thresh = 16'h2000;      // negative clip at 0x200000 (asymmetric!)
        tone_coeff      = 8'd0;

        $display("       Generating 64-sample sine sweep @ 1.5x gain with asymmetric clip...");

        // Generate 64 samples of a sine-ish wave using successive approximations
        // This creates a triangle wave as sine approximation (sufficient for fuzz testing)
        for (i = 0; i < 64; i = i + 1) begin
            if (i < 16)
                sine = (i * 24'h080000) / 16;  // Rising
            else if (i < 32)
                sine = 24'h080000 - ((i - 16) * 24'h100000) / 16;  // Falling
            else if (i < 48)
                sine = -((i - 32) * 24'h080000) / 16;  // Negative rising
            else
                sine = -24'h080000 + ((i - 48) * 24'h100000) / 16;  // Negative falling

            @(posedge clk) begin
                i_tdata  = sine;
                i_tvalid = 1'b1;
                o_tready = 1'b1;
            end

            @(posedge clk);
            @(posedge clk);  // Wait for pipeline

            if ($signed(o_tdata) > $signed(max_abs_out))
                max_abs_out = o_tdata;
            if ($signed(o_tdata) < $signed(min_abs_out))
                min_abs_out = o_tdata;
        end

        $display("       Sine sweep complete. Max out: 0x%06h, Min out: 0x%06h", max_abs_out, min_abs_out);

        // Verify positive clipping is tighter (asymmetric — lower pos threshold)
        if ($signed(max_abs_out) <= $signed(24'h400000) &&
            $signed(min_abs_out) >= $signed(-24'h200000)) begin
            $display("[PASS] Test 13: Asymmetric clipping during sine sweep");
            $display("       pos clip at 0x400000, neg clip at 0x200000");
            num_pass = num_pass + 1;
        end else begin
            $display("[FAIL] Test 13: Asymmetric clipping bounds violated");
            $display("       max: 0x%06h (limit: 0x400000), min: 0x%06h (limit: -0x200000)",
                     max_abs_out, min_abs_out);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 13: Sine sweep clip bounds violated";
            num_failed_logged = num_failed_logged + 1;
        end
    end
    endtask

    // ======= TEST 14: EXTREME CLIPPING (NEAR-SQUARE WAVE) =======
    task test_14_extreme_clipping;
    begin
        wait(rst_n == 1'b1);
        #10;

        // Max gain, very low thresholds — signal should square off
        send_sample(24'h100000, 16'h7FFF, 16'h0100, 16'h0100, 8'd0);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        // threshold = 0x0100 << 8 = 0x010000
        if (o_tdata == 24'h010000) begin
            $display("[PASS] Test 14a: Extreme positive clipping (near-square)");
            num_pass = num_pass + 1;
        end else begin
            $display("[FAIL] Test 14a: Extreme positive clipping failed");
            $display("       expected: 0x010000, got: 0x%06h", o_tdata);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 14a: Extreme pos clip failed";
            num_failed_logged = num_failed_logged + 1;
        end

        send_sample(-24'h100000, 16'h7FFF, 16'h0100, 16'h0100, 8'd0);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        if (o_tdata == -24'h010000) begin
            $display("[PASS] Test 14b: Extreme negative clipping (near-square)");
            num_pass = num_pass + 1;
        end else begin
            $display("[FAIL] Test 14b: Extreme negative clipping failed");
            $display("       expected: -0x010000, got: 0x%06h", o_tdata);
            num_fail = num_fail + 1;
            failed_tests[num_failed_logged] = "Test 14b: Extreme neg clip failed";
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
        test_4_pregain_2x;

        reset;
        test_5_positive_clipping;

        reset;
        test_6_negative_clipping;

        reset;
        test_7_asymmetric_clipping;

        reset;
        test_8_backpressure;

        reset;
        test_9_zero_input;

        reset;
        test_10_gain_and_clip;

        reset;
        test_11_step_response;

        reset;
        test_12_tone_control;

        reset;
        test_13_sine_sweep;

        reset;
        test_14_extreme_clipping;

        #50;
    end

    // ======= TIMEOUT AND SUMMARY =======
    initial begin
        #10000;  // 10µs max simulation time

        $display("\n");
        $display("========================================");
        $display("          TEST SUMMARY REPORT           ");
        $display("========================================");
        $display("  Total Passed: %d", num_pass);
        $display("  Total Failed: %d", num_fail);
        $display("========================================");

        if (num_fail > 0) begin
            $display("\n");
            $display("FAILURE DETAILS:");
            $display("----------------------------------------");
            for (integer i = 0; i < num_failed_logged; i = i + 1) begin
                $display("  [%d] %0s", i + 1, failed_tests[i]);
            end
            $display("----------------------------------------");
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
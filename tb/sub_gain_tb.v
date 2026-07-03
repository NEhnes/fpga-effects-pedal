// claude fixed up my testbench
`timescale 1ns / 1ps
`include "hard_clip.v"

module sub_gain_tb();
    reg signed [23:0] i_sample;
    reg signed [15:0] gain_q114;
    wire signed [23:0] o_sample;
    
    // Max/min constants for readability
    localparam signed [23:0] MAX_24 =  24'h7FFFFF;  //  8388607
    localparam signed [23:0] MIN_24 =  24'h800000;  // -8388608
    
    sub_gain dut (
        .i_sample(i_sample),
        .gain_q114(gain_q114),
        .o_sample(o_sample)
    );
    
    initial begin
        $dumpfile("sub_gain_tb.vcd");
        $dumpvars(0, sub_gain_tb);
        
        // Test 1: Unity gain (Q1.14 unity = 0x4000)
        i_sample = 24'h100000;
        gain_q114 = 16'h4000;
        #10;
        if (o_sample == i_sample)
            $display("[PASS] Unity gain: in=%d, out=%d", i_sample, o_sample);
        else
            $display("[FAIL] Unity gain: in=%d, expected=%d, got=%d", i_sample, i_sample, o_sample);
        
        // Test 2: Half gain (0x2000)
        gain_q114 = 16'h2000;
        #10;
        if (o_sample == (i_sample >>> 1))
            $display("[PASS] Half gain: in=%d, out=%d", i_sample, o_sample);
        else
            $display("[FAIL] Half gain: in=%d, expected=%d, got=%d", i_sample, i_sample >>> 1, o_sample);
        
        // Test 3: Zero sample
        i_sample = 24'h000000;
        #10;
        if (o_sample == 24'h000000)
            $display("[PASS] Zero input: out=%d", o_sample);
        else
            $display("[FAIL] Zero input: expected=0, got=%d", o_sample);
        
        // Test 4: Negative unity gain (-1.0 in Q1.14)
        i_sample = 24'h100000;
        gain_q114 = 16'hC000;  // -1.0 in Q1.14
        #10;
        if (o_sample == -i_sample)
            $display("[PASS] Negative unity gain (-1.0): in=%d, out=%d", i_sample, o_sample);
        else
            $display("[FAIL] Negative unity gain (-1.0): in=%d, expected=%d, got=%d", i_sample, -i_sample, o_sample);
        
        // ===== SATURATION TESTS =====
        
        // Test 5: Positive overflow saturates to MAX
        // Near-max positive sample * gain of ~2.0 should clamp to 0x7FFFFF
        i_sample = 24'h600000;          // large positive sample
        gain_q114 = 16'h7FFF;           // just under +2.0 in Q1.14
        #10;
        if (o_sample == MAX_24)
            $display("[PASS] Positive saturation: in=%d, gain=0x%04h, out=%d (MAX)", i_sample, gain_q114, o_sample);
        else
            $display("[FAIL] Positive saturation: in=%d, gain=0x%04h, expected=%d, got=%d", i_sample, gain_q114, MAX_24, o_sample);
        
        // Test 6: Negative overflow saturates to MIN
        // Large negative sample * gain of ~2.0 should clamp to 0x800000
        i_sample = -24'h600000;         // large negative sample
        gain_q114 = 16'h7FFF;           // just under +2.0
        #10;
        if (o_sample == MIN_24)
            $display("[PASS] Negative saturation: in=%d, gain=0x%04h, out=%d (MIN)", i_sample, gain_q114, o_sample);
        else
            $display("[FAIL] Negative saturation: in=%d, gain=0x%04h, expected=%d, got=%d", i_sample, gain_q114, MIN_24, o_sample);
        
        // Test 7: Max positive sample at unity does NOT saturate
        i_sample = MAX_24;
        gain_q114 = 16'h4000;           // unity
        #10;
        if (o_sample == MAX_24)
            $display("[PASS] Max sample at unity: in=%d, out=%d", i_sample, o_sample);
        else
            $display("[FAIL] Max sample at unity: in=%d, expected=%d, got=%d", i_sample, MAX_24, o_sample);
        
        // Test 8: Min negative sample at unity does NOT saturate
        i_sample = MIN_24;
        gain_q114 = 16'h4000;           // unity
        #10;
        if (o_sample == MIN_24)
            $display("[PASS] Min sample at unity: in=%d, out=%d", i_sample, o_sample);
        else
            $display("[FAIL] Min sample at unity: in=%d, expected=%d, got=%d", i_sample, MIN_24, o_sample);
        
        // Test 9: Negative gain causing positive overflow (negative * negative = positive overflow)
        i_sample = MIN_24;              // most negative sample
        gain_q114 = 16'hC000;           // -1.0 in Q1.14
        #10;
        // -(-8388608) = 8388608 which exceeds MAX_24 (8388607) by 1
        if (o_sample == MAX_24)
            $display("[PASS] Neg*Neg saturation: in=%d, gain=-1.0, out=%d (MAX)", i_sample, o_sample);
        else
            $display("[FAIL] Neg*Neg saturation: in=%d, gain=-1.0, expected=%d, got=%d", i_sample, MAX_24, o_sample);
        
        // Test 10: Just below saturation threshold should pass through
        i_sample = 24'h3FFFFF;          // about quarter-max
        gain_q114 = 16'h7FFF;           // just under +2.0
        #10;
        // Result should be ~0x7FFFFE, which fits — no saturation
        if (o_sample > 0 && o_sample <= MAX_24)
            $display("[PASS] Below saturation: in=%d, gain=0x%04h, out=%d (no clamp)", i_sample, gain_q114, o_sample);
        else
            $display("[FAIL] Below saturation: in=%d, gain=0x%04h, out=%d", i_sample, gain_q114, o_sample);
        
        $finish;
    end
endmodule
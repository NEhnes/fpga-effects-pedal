// claude fixed up my testbench
`timescale 1ns / 1ps
`include "hard_clip.v"

module sub_gain_tb();
    reg signed [23:0] i_sample;
    reg signed [15:0] gain_q114;
    wire signed [23:0] o_sample;
    
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
        
        $finish;
    end
endmodule
`timescale 1ns / 1ps
`include "hard_clip.v"

module tb_sub_gain();
    reg signed [23:0] i_sample;
    reg signed [15:0] gain_q115;
    wire signed [23:0] o_sample;
    
    sub_gain dut (
        .i_sample(i_sample),
        .gain_q115(gain_q115),
        .o_sample(o_sample)
    );
    
    initial begin
        $dumpfile("sub_gain_tb.vcd");
        $dumpvars(0, tb_sub_gain);
        
        // Test 1: Unity gain
        i_sample = 24'h100000;
        gain_q115 = 16'h8000;
        #10;
        $display("Unity: in=%d, gain=%h, out=%d", i_sample, gain_q115, o_sample);
        
        // Test 2: Half gain
        gain_q115 = 16'h4000;
        #10;
        $display("Half: in=%d, out=%d", i_sample, o_sample);
        
        // Test 3: Zero sample
        i_sample = 24'h000000;
        #10;
        $display("Zero: out=%d", o_sample);
        
        $finish;
    end
endmodule
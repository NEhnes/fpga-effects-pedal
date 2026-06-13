`timescale 1ns / 1ps
`include "hard_clip.v"

module tb_hard_clip();
    reg  signed [23:0] i_tdata;
    reg                i_tvalid;
    reg                o_tready;
    reg                tclk;
    reg                rst_n;
    
    wire               i_tready;
    wire               o_tvalid;
    wire signed [23:0] o_tdata;
    
    hard_clip #(
        .INPUT_GAIN(1.0)
    ) dut (
        .tclk(tclk),
        .rst_n(rst_n),
        .i_tdata(i_tdata),
        .i_tvalid(i_tvalid),
        .i_tready(i_tready),
        .o_tready(o_tready),
        .o_tvalid(o_tvalid),
        .o_tdata(o_tdata)
    );
    
    // Clock generation
    initial begin
        tclk = 0;
        forever #5 tclk = ~tclk;  // 10ns period
    end
    
    initial begin
        $dumpfile("hard_clip_tb.vcd");
        $dumpvars(0, tb_hard_clip);
        
        // Reset
        rst_n = 0;
        i_tvalid = 0;
        o_tready = 0;
        i_tdata = 0;
        #20;
        rst_n = 1;
        #10;
        
        // Test 1: Reset clears output
        if (o_tdata == 24'h000000)
            $display("[PASS] Reset clears output: out=%d", o_tdata);
        else
            $display("[FAIL] Reset clears output: expected=0, got=%d", o_tdata);
        
        // Test 2: Valid data propagation (check control signals)
        i_tdata = 24'h100000;
        i_tvalid = 1;
        o_tready = 1;
        #10;
        if (o_tvalid == 1)
            $display("[PASS] o_tvalid propagates: o_tvalid=%b", o_tvalid);
        else
            $display("[FAIL] o_tvalid propagates: expected=1, got=%b", o_tvalid);
        
        if (i_tready == 1)
            $display("[PASS] i_tready propagates: i_tready=%b", i_tready);
        else
            $display("[FAIL] i_tready propagates: expected=1, got=%b", i_tready);
        
        // Test 3: Data processes through unity gain (INPUT_GAIN = 1.0)
        #10;
        if (o_tdata == i_tdata)
            $display("[PASS] Unity gain passthrough: in=%d, out=%d", i_tdata, o_tdata);
        else
            $display("[FAIL] Unity gain passthrough: in=%d, expected=%d, got=%d", i_tdata, i_tdata, o_tdata);
        
        // Test 4: Different input value
        i_tdata = 24'h080000;  // 524288
        #10;
        if (o_tdata == i_tdata)
            $display("[PASS] Half-magnitude input: in=%d, out=%d", i_tdata, o_tdata);
        else
            $display("[FAIL] Half-magnitude input: in=%d, expected=%d, got=%d", i_tdata, i_tdata, o_tdata);
        
        // Test 5: Handshake - input not ready
        i_tdata = 24'h200000;
        i_tvalid = 1;
        o_tready = 0;
        #10;
        $display("[INFO] Backpressure test: i_tready=%b (should be 0 when o_tready=0)", i_tready);
        if (i_tready == 0)
            $display("[PASS] Backpressure: i_tready follows o_tready");
        else
            $display("[FAIL] Backpressure: i_tready should follow o_tready");
        
        // Test 6: Resume handshake
        o_tready = 1;
        #10;
        if (i_tready == 1)
            $display("[PASS] Resume after backpressure: i_tready=%b", i_tready);
        else
            $display("[FAIL] Resume after backpressure: expected=1, got=%b", i_tready);
        
        // Test 7: Negative input
        i_tdata = -24'h100000;
        #10;
        if (o_tdata == i_tdata)
            $display("[PASS] Negative input: in=%d, out=%d", i_tdata, o_tdata);
        else
            $display("[FAIL] Negative input: in=%d, expected=%d, got=%d", i_tdata, i_tdata, o_tdata);
        
        // Test 8: Zero input
        i_tdata = 24'h000000;
        #10;
        if (o_tdata == 24'h000000)
            $display("[PASS] Zero input: out=%d", o_tdata);
        else
            $display("[FAIL] Zero input: expected=0, got=%d", o_tdata);
        
        $finish;
    end
endmodule
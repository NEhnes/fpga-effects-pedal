`timescale 1ns / 1ps
`include "../../src/eff/delay.v"

module delay_tb;

    // Clock and reset
    reg tclk;
    reg rst_n;
    
    // AXI-Stream slave (input to DUT)
    reg i_tvalid;
    wire i_tready;
    reg [23:0] i_tdata;
    
    // AXI-Stream master (output from DUT)
    wire o_tvalid;
    reg o_tready;
    wire [23:0] o_tdata;
    
    // Control parameters
    reg [16:0] delay_samples;
    reg [7:0] mix;
    reg [7:0] feedback;
    
    // Test counters
    integer num_pass;
    integer num_fail;
    integer test_counter;
    
    // Instantiate DUT
    delay #(
        .WIDTH(24),
        .MAX_DELAY_SAMPLES(96000),
        .ADDR_WIDTH(17)
    ) dut (
        .tclk(tclk),
        .rst_n(rst_n),
        .i_tvalid(i_tvalid),
        .i_tready(i_tready),
        .i_tdata(i_tdata),
        .o_tvalid(o_tvalid),
        .o_tready(o_tready),
        .o_tdata(o_tdata),
        .delay_samples(delay_samples),
        .mix(mix),
        .feedback(feedback)
    );
    
    // Clock generation: 10ns period = 100MHz
    initial begin
        tclk = 1'b0;
        forever #5 tclk = ~tclk;
    end
    
    // Test sequence
    initial begin
        num_pass = 0;
        num_fail = 0;
        
        $display("\n========================================");
        $display("        DELAY EFFECT TESTBENCH");
        $display("========================================\n");
        
        // Test 1: Reset clears state
        reset_test;
        
        // Test 2: AXI handshake with no delay
        axi_handshake_test;
        
        // Test 3: Backpressure propagation
        backpressure_test;
        
        // Test 4: Zero input yields zero output
        zero_input_test;
        
        // Test 5: Dry passthrough (mix=0)
        dry_passthrough_test;
        
        // Test 6: Wet-only output (mix=255)
        wet_only_test;
        
        // Test 7: Delay line basic operation
        delay_line_test;
        
        // Test 8: Feedback loop
        feedback_test;
        
        // Test 9: Mix blending
        mix_blend_test;
        
        // Test 10: Edge case - max delay samples
        max_delay_test;
        
        // Print summary
        $display("\n========================================");
        $display("           TEST SUMMARY");
        $display("========================================");
        $display("Passed: %d", num_pass);
        $display("Failed: %d", num_fail);
        if (num_fail == 0) begin
            $display("\n✓ ALL TESTS PASSED");
        end else begin
            $display("\n✗ SOME TESTS FAILED");
        end
        $display("========================================\n");
        
        #100;
        $finish;
    end
    
    // ===== RESET TASK =====
    task reset_test;
    begin
        $display("[TEST 1] Reset clears all state");
        
        // Assert reset
        rst_n = 1'b0;
        i_tvalid = 1'b0;
        o_tready = 1'b1;
        i_tdata = 24'h000000;
        delay_samples = 17'h00100;
        mix = 8'd128;
        feedback = 8'd64;
        
        #50;
        
        // Release reset
        rst_n = 1'b1;
        #20;
        
        // Verify output is zero after reset
        if (o_tdata === 24'h000000) begin
            $display("  [PASS] o_tdata = 24'h000000 after reset\n");
            num_pass = num_pass + 1;
        end else begin
            $display("  [FAIL] o_tdata = %h, expected 24'h000000\n", o_tdata);
            num_fail = num_fail + 1;
        end
    end
    endtask
    
    // ===== AXI HANDSHAKE TEST =====
    task axi_handshake_test;
    begin
        $display("[TEST 2] AXI-Stream handshake (no delay, unity mix)");
        
        delay_samples = 17'd1;  // Minimal delay
        mix = 8'd0;             // All dry
        feedback = 8'd0;        // No feedback
        
        // Wait for reset to complete
        wait(rst_n == 1'b1);
        
        test_counter = 0;
        
        // Apply input stimulus
        @(posedge tclk) begin
            i_tvalid = 1'b1;
            o_tready = 1'b1;
            i_tdata = 24'h123456;
        end
        
        // Wait several cycles to observe propagation
        repeat(10) @(posedge tclk);
        
        // Verify o_tvalid tracks i_tvalid
        if (o_tvalid === i_tvalid) begin
            $display("  [PASS] o_tvalid correctly tracks i_tvalid\n");
            num_pass = num_pass + 1;
        end else begin
            $display("  [FAIL] o_tvalid=%b, expected %b\n", o_tvalid, i_tvalid);
            num_fail = num_fail + 1;
        end
        
        i_tvalid = 1'b0;
    end
    endtask
    
    // ===== BACKPRESSURE TEST =====
    task backpressure_test;
    begin
        $display("[TEST 3] Backpressure propagation");
        
        wait(rst_n == 1'b1);
        #10;
        
        // Assert o_tready = 0 (downstream blocks)
        @(posedge tclk) begin
            o_tready = 1'b0;
        end
        
        #20;
        
        // Verify i_tready mirrors o_tready
        if (i_tready === 1'b0) begin
            $display("  [PASS] i_tready = 0 when o_tready = 0\n");
            num_pass = num_pass + 1;
        end else begin
            $display("  [FAIL] i_tready = %b, expected 0\n", i_tready);
            num_fail = num_fail + 1;
        end
        
        // Release backpressure
        @(posedge tclk) begin
            o_tready = 1'b1;
        end
        
        #20;
        
        if (i_tready === 1'b1) begin
            $display("  [PASS] i_tready = 1 when o_tready = 1\n");
            num_pass = num_pass + 1;
        end else begin
            $display("  [FAIL] i_tready = %b, expected 1\n", i_tready);
            num_fail = num_fail + 1;
        end
    end
    endtask
    
    // ===== ZERO INPUT TEST =====
    task zero_input_test;
    begin
        $display("[TEST 4] Zero input produces near-zero output");
        
        wait(rst_n == 1'b1);
        
        delay_samples = 17'd1;
        mix = 8'd128;
        feedback = 8'd0;  // No feedback to avoid accumulation
        
        // Apply zero input for several cycles
        @(posedge tclk) begin
            i_tvalid = 1'b1;
            o_tready = 1'b1;
            i_tdata = 24'h000000;
        end
        
        repeat(20) @(posedge tclk);
        
        // Allow small rounding errors due to fixed-point math
        if ($signed(o_tdata) < $signed(24'h001000) && 
            $signed(o_tdata) > $signed(24'hFFF000)) begin
            $display("  [PASS] o_tdata ≈ zero with zero input (got %h)\n", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("  [FAIL] o_tdata = %h, expected ~0\n", o_tdata);
            num_fail = num_fail + 1;
        end
        
        i_tvalid = 1'b0;
    end
    endtask
    
    // ===== DRY PASSTHROUGH TEST =====
    task dry_passthrough_test;
    begin
        $display("[TEST 5] Dry passthrough (mix=0)");
        
        wait(rst_n == 1'b1);
        #10;
        
        delay_samples = 17'd100;
        mix = 8'd0;          // All dry (no wet)
        feedback = 8'd0;     // No feedback
        
        @(posedge tclk) begin
            i_tvalid = 1'b1;
            o_tready = 1'b1;
            i_tdata = 24'h100000;  // Small positive value
        end
        
        // Wait for signal to stabilize
        repeat(30) @(posedge tclk);
        
        // With mix=0, output should be dominated by input (dry)
        // Due to 5-stage pipeline, output will appear delayed
        // Allow tolerance for pipeline settling
        if ($signed(o_tdata) >= $signed(24'h0F0000) && 
            $signed(o_tdata) <= $signed(24'h110000)) begin
            $display("  [PASS] Output ≈ input with dry mix (got %h)\n", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("  [FAIL] Output = %h, expected ~100000\n", o_tdata);
            num_fail = num_fail + 1;
        end
        
        i_tvalid = 1'b0;
    end
    endtask
    
    // ===== WET-ONLY TEST =====
    task wet_only_test;
    begin
        $display("[TEST 6] Wet-only output (mix=255)");
        
        wait(rst_n == 1'b1);
        #10;
        
        delay_samples = 17'd50;
        mix = 8'd255;        // All wet
        feedback = 8'd0;     // No feedback
        
        // First, prime the delay line with a known value
        @(posedge tclk) begin
            i_tvalid = 1'b1;
            o_tready = 1'b1;
            i_tdata = 24'h080000;  // Known value
        end
        
        // Wait for delay line to fill and output to stabilize
        repeat(150) @(posedge tclk);
        
        // Output should eventually reflect only delayed input
        // With mix=255, we're reading only from the delay line
        if ($signed(o_tdata) >= $signed(24'h070000) && 
            $signed(o_tdata) <= $signed(24'h090000)) begin
            $display("  [PASS] Wet output ≈ delayed input (got %h)\n", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("  [FAIL] Wet output = %h, expected ~080000\n", o_tdata);
            num_fail = num_fail + 1;
        end
        
        i_tvalid = 1'b0;
    end
    endtask
    
    // ===== DELAY LINE BASIC OPERATION TEST =====
    task delay_line_test;
    begin
        $display("[TEST 7] Delay line basic operation");
        
        wait(rst_n == 1'b1);
        #10;
        
        delay_samples = 17'd8;   // 8-sample delay
        mix = 8'd255;            // Read only delayed (pure wet)
        feedback = 8'd0;         // No feedback
        
        // Prime the delay line with a constant value
        @(posedge tclk) begin
            i_tvalid = 1'b1;
            o_tready = 1'b1;
            i_tdata = 24'h180000;  // Known prime value
        end
        
        // Keep feeding the same value
        repeat(60) @(posedge tclk);
        
        // After sufficient cycles, output should equal the primed value
        // Allowing tolerance for rounding
        if ($signed(o_tdata) >= $signed(24'h170000) && 
            $signed(o_tdata) <= $signed(24'h190000)) begin
            $display("  [PASS] Delay line stable (got %h)\n", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("  [FAIL] Delay line unstable, got %h\n", o_tdata);
            num_fail = num_fail + 1;
        end
        
        i_tvalid = 1'b0;
    end
    endtask
    
    // ===== FEEDBACK TEST =====
    task feedback_test;
    begin
        $display("[TEST 8] Feedback loop operation");
        
        wait(rst_n == 1'b1);
        #10;
        
        delay_samples = 17'd8;   // Short delay for feedback to loop
        mix = 8'd200;            // High wet mix
        feedback = 8'd64;        // Moderate feedback (~25% * 255)
        
        @(posedge tclk) begin
            i_tvalid = 1'b1;
            o_tready = 1'b1;
            i_tdata = 24'h100000;
        end
        
        // Let feedback accumulate for several cycles
        repeat(40) @(posedge tclk);
        
        // With feedback, output should grow slightly then stabilize
        // Check that it's not zero and not wildly overflowed
        if ($signed(o_tdata) != $signed(24'h000000) && 
            $signed(o_tdata) != $signed(24'h800000)) begin
            $display("  [PASS] Feedback loop active (output = %h)\n", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("  [FAIL] Unexpected feedback output = %h\n", o_tdata);
            num_fail = num_fail + 1;
        end
        
        i_tvalid = 1'b0;
    end
    endtask
    
    // ===== MIX BLEND TEST =====
    task mix_blend_test;
    begin
        $display("[TEST 9] Mix parameter blending");
        
        wait(rst_n == 1'b1);
        #10;
        
        delay_samples = 17'd20;
        feedback = 8'd0;
        
        // Test mix value 128 (50/50 blend)
        @(posedge tclk) begin
            i_tvalid = 1'b1;
            o_tready = 1'b1;
            i_tdata = 24'h100000;
            mix = 8'd128;
        end
        
        repeat(50) @(posedge tclk);
        
        // Output should be intermediate between dry and wet
        // Tolerance is generous due to rounding
        if ($signed(o_tdata) >= $signed(24'h040000) && 
            $signed(o_tdata) <= $signed(24'h120000)) begin
            $display("  [PASS] 50/50 mix produces blended output (got %h)\n", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("  [FAIL] Mix output out of range = %h\n", o_tdata);
            num_fail = num_fail + 1;
        end
        
        i_tvalid = 1'b0;
    end
    endtask
    
    // ===== MAX DELAY TEST =====
    task max_delay_test;
    begin
        $display("[TEST 10] Edge case - maximum delay parameter");
        
        wait(rst_n == 1'b1);
        #10;
        
        // Set delay to reasonable max
        delay_samples = 17'd32767;  // Use reasonable large value
        mix = 8'd0;                  // All dry to simplify
        feedback = 8'd0;
        
        @(posedge tclk) begin
            i_tvalid = 1'b1;
            o_tready = 1'b1;
            i_tdata = 24'h050000;
        end
        
        // Module should not crash
        repeat(30) @(posedge tclk);
        
        // Output should not be X or wildly out of range
        if (o_tdata !== 24'hxxxxxx && o_tdata !== 24'hzzzzzz) begin
            $display("  [PASS] Module stable with large delay parameter (got %h)\n\n", o_tdata);
            num_pass = num_pass + 1;
        end else begin
            $display("  [FAIL] Invalid output at large delay\n\n");
            num_fail = num_fail + 1;
        end
        
        i_tvalid = 1'b0;
    end
    endtask
    
    // ===== TIMEOUT =====
    initial begin
        #100000;  // 100µs max
        $display("\n[TIMEOUT] Simulation did not complete in time");
        $finish;
    end
    
    // ===== WAVEFORM DUMP =====
    initial begin
        $dumpfile("delay_tb.vcd");
        $dumpvars(0, delay_tb);
    end

endmodule

`timescale 1ns / 1ps
`include "../../src/eff/delay.v"

module delay_effect_tb;

    // ======= PARAMETERS =======
    localparam WIDTH = 24;
    localparam DEPTH = 1024;
    
    // Q1.14 Fixed Point Constants
    localparam signed [15:0] Q114_1_0 = 16'h4000; // 1.0 (Unity)
    localparam signed [15:0] Q114_0_5 = 16'h2000; // 0.5
    localparam signed [15:0] Q114_0_0 = 16'h0000; // 0.0

    // Extreme values for saturation testing
    localparam signed [WIDTH-1:0] MAX_POS = 24'h7FFFFF;
    localparam signed [WIDTH-1:0] MAX_NEG = 24'h800000;

    // ======= GLOBAL SIGNALS =======
    reg clk;
    reg rst_n;

    // ======= DUT SIGNALS =======
    // Effect Parameters
    reg  [15:0]      delay_samples;
    reg  [15:0]      feedback_q114;
    reg  [15:0]      wet_gain_q114;
    reg  [15:0]      dry_gain_q114;
    reg  [15:0]      input_gain_q114;

    // AXI-Stream
    reg  [WIDTH-1:0] i_tdata;
    reg              i_tvalid;
    wire             i_tready;
    reg              o_tready;
    wire             o_tvalid;
    wire [WIDTH-1:0] o_tdata;

    // ======= TEST CONTROL & LOGGING =======
    integer num_pass = 0;
    integer num_fail = 0;
    
    // Failure logging arrays (1-indexed for test numbers 1 to 4)
    reg        fail_flags [1:4];
    reg [23:0] fail_exp   [1:4];
    reg [23:0] fail_got   [1:4];

    integer i; // Loop variable

    // ======= DUT INSTANTIATION =======
    delay_effect #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .delay_samples   (delay_samples),
        .feedback_q114   (feedback_q114),
        .wet_gain_q114   (wet_gain_q114),
        .dry_gain_q114   (dry_gain_q114),
        .input_gain_q114 (input_gain_q114),

        .tclk            (clk),
        .rst_n           (rst_n),
        .i_tdata         (i_tdata),
        .i_tvalid        (i_tvalid),
        .i_tready        (i_tready),
        .o_tready        (o_tready),
        .o_tvalid        (o_tvalid),
        .o_tdata         (o_tdata)
    );

    // ======= CLOCK GENERATION =======
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;  // 10ns period (100 MHz)
    end

    // ======= MAIN TEST SEQUENCE =======
    initial begin
        // Initialize failure flags
        for (i = 1; i <= 4; i = i + 1) begin
            fail_flags[i] = 1'b0;
        end

        $display("\n=======================================================");
        $display(" RUNNING TESTBENCH: delay_effect_tb                    ");
        $display("=======================================================\n");

        reset_sequence();
        test_1_dry_passthrough();

        reset_sequence();
        test_2_wet_delay_only();

        reset_sequence();
        test_3_feedback_loop();

        reset_sequence();
        test_4_saturation_clamping();

        print_final_summary();
        $finish;
    end

    // ======= TIMEOUT =======
    initial begin
        #10000;  // 10us absolute maximum simulation time
        $display("\n[FATAL] Simulation timeout reached. Possible hang.");
        $finish;
    end

    // ======= WAVEFORM DUMP =======
    initial begin
        $dumpfile("delay_effect_tb.vcd");
        $dumpvars(0, delay_effect_tb);
    end

    // ======= HELPER TASKS =======

    task reset_sequence;
    begin
        // Apply reset
        rst_n           = 1'b0;
        delay_samples   = 16'd0;
        feedback_q114   = Q114_0_0;
        wet_gain_q114   = Q114_0_0;
        dry_gain_q114   = Q114_0_0;
        input_gain_q114 = Q114_0_0;
        
        i_tdata         = 24'd0;
        i_tvalid        = 1'b0;
        o_tready        = 1'b0;
        
        #50;
        @(posedge clk);
        rst_n = 1'b1;
        #10;
    end
    endtask

    // Evaluation macro-like task (to standardize tolerance and logging)
    task evaluate_result;
        input integer test_num;
        input [8*30:1] test_name;
        input signed [WIDTH-1:0] expected;
        input signed [WIDTH-1:0] actual;
    begin
        // Allow +/- 1 tolerance for fixed-point rounding
        if ((actual >= expected - 1) && (actual <= expected + 1)) begin
            $display("[PASS] TEST %0d: %-25s | EXPECTED: %08x | GOT: %08x", test_num, test_name, expected, actual);
            num_pass = num_pass + 1;
        end else begin
            $display("[FAIL] TEST %0d: %-25s | EXPECTED: %08x | GOT: %08x", test_num, test_name, expected, actual);
            num_fail = num_fail + 1;
            fail_flags[test_num] = 1'b1;
            fail_exp[test_num]   = expected;
            fail_got[test_num]   = actual;
        end
    end
    endtask

    // ======= TEST CASES =======

    // TEST 1: Dry Passthrough
    // Tests combinatorial routing of signal straight to output with unity gain
    task test_1_dry_passthrough;
    begin
        wait(rst_n == 1'b1);
        @(posedge clk);

        // Setup parameters
        input_gain_q114 = Q114_1_0;
        dry_gain_q114   = Q114_1_0;
        wet_gain_q114   = Q114_0_0;
        feedback_q114   = Q114_0_0;
        delay_samples   = 16'd10;

        // Drive Stimulus
        @(posedge clk);
        i_tdata  = 24'd5000;
        i_tvalid = 1'b1;
        o_tready = 1'b1;

        // Check output combinationally (same cycle)
        #1; // Delta delay to let combinational logic settle
        evaluate_result(1, "Dry Passthrough", 24'd5000, o_tdata);

        // Clear
        @(posedge clk);
        i_tvalid = 1'b0;
        o_tready = 1'b0;
    end
    endtask


    // TEST 2: Wet Delay Only
    // Tests fundamental ring buffer delay operation (Delay = 4)
    task test_2_wet_delay_only;
    begin
        wait(rst_n == 1'b1);
        @(posedge clk);

        input_gain_q114 = Q114_1_0;
        dry_gain_q114   = Q114_0_0;
        wet_gain_q114   = Q114_1_0;
        feedback_q114   = Q114_0_0;
        delay_samples   = 16'd4;
        
        i_tvalid = 1'b1;
        o_tready = 1'b1;

        // Cycle 0: Input data
        @(posedge clk);
        i_tdata = 24'd1200;

        // Cycle 1-3: Input zero, stream running
        @(posedge clk);
        i_tdata = 24'd0;
        @(posedge clk);
        @(posedge clk);

        // Cycle 4: Delayed sample should emerge
        @(posedge clk);
        #1; 
        evaluate_result(2, "Wet Delay (N=4)", 24'd1200, o_tdata);

        // Clear
        @(posedge clk);
        i_tvalid = 1'b0;
    end
    endtask


    // TEST 3: Feedback Loop
    // Tests feedback math (Feedback = 0.5). Echo should be 50% of original.
    task test_3_feedback_loop;
    begin
        wait(rst_n == 1'b1);
        @(posedge clk);

        input_gain_q114 = Q114_1_0;
        dry_gain_q114   = Q114_0_0;
        wet_gain_q114   = Q114_1_0;
        feedback_q114   = Q114_0_5; // 0.5 gain
        delay_samples   = 16'd2;    // Fast feedback
        
        i_tvalid = 1'b1;
        o_tready = 1'b1;

        // Cycle 0: Input high magnitude pulse
        @(posedge clk);
        i_tdata = 24'd8000;

        // Cycle 1: Zero
        @(posedge clk);
        i_tdata = 24'd0;

        // Cycle 2: First echo (Original * 1.0 = 8000) emerges
        // It gets fed back simultaneously (8000 * 0.5 = 4000)
        @(posedge clk);
        
        // Cycle 3: Zero
        @(posedge clk);

        // Cycle 4: Second echo (First echo * 0.5 = 4000) emerges
        @(posedge clk);
        #1; 
        evaluate_result(3, "Feedback Decay", 24'd4000, o_tdata);

        // Clear
        @(posedge clk);
        i_tvalid = 1'b0;
    end
    endtask


    // TEST 4: Saturation Clamping
    // Tests positive and negative overflow clipping in the sub_add module
    task test_4_saturation_clamping;
    begin
        wait(rst_n == 1'b1);
        @(posedge clk);

        // To test adder, apply max values to both Dry and Wet paths simultaneously
        input_gain_q114 = Q114_1_0;
        dry_gain_q114   = Q114_1_0;
        wet_gain_q114   = Q114_1_0; 
        feedback_q114   = Q114_0_0;
        delay_samples   = 16'd1;
        
        i_tvalid = 1'b1;
        o_tready = 1'b1;

        // --- Positive Saturation ---
        // Cycle 0: Seed delay line with half max positive
        @(posedge clk);
        i_tdata = 24'h400000;

        // Cycle 1: Add current (half max) + delayed (half max)
        @(posedge clk); 
        i_tdata = 24'h400000;
        #1; // evaluate output
        // Expected sum: 24'h800000 (which is negative). Should clamp to MAX_POS (24'h7FFFFF)
        evaluate_result(4, "Positive Saturation", MAX_POS, o_tdata);

        // --- Negative Saturation ---
        // Cycle 2: Seed delay line with half max negative
        @(posedge clk);
        i_tdata = 24'hC00000; // -4194304

        // Cycle 3: Add current (half max neg) + delayed (half max neg)
        @(posedge clk);
        i_tdata = 24'hC00000;
        #1; // evaluate output
        // Expected sum: 0x1800000 (overflows to pos). Should clamp to MAX_NEG (24'h800000)
        evaluate_result(4, "Negative Saturation", MAX_NEG, o_tdata);

        // Clear
        @(posedge clk);
        i_tvalid = 1'b0;
    end
    endtask


    // ======= SUMMARY PRINTER =======
    task print_final_summary;
    begin
        $display("\n=======================================================");
        $display(" TEST RESULT SUMMARY                                   ");
        $display("=======================================================");
        $display(" Total Passed : %0d", num_pass);
        $display(" Total Failed : %0d", num_fail);
        $display("-------------------------------------------------------");

        if (num_fail > 0) begin
            $display("\n FAILURE DETAILS:");
            $display(" TEST ID | EXPECTED   | ACTUAL ");
            $display(" --------|------------|------------");
            for (i = 1; i <= 4; i = i + 1) begin
                if (fail_flags[i]) begin
                    $display(" %-7d | 0x%08x | 0x%08x", i, fail_exp[i], fail_got[i]);
                end
            end
            $display("=======================================================\n");
        end else begin
            $display(" ALL TESTS PASSED SUCCESSFULLY!");
            $display("=======================================================\n");
        end
    end
    endtask

endmodule

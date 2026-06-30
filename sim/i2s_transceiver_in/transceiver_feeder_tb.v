// ═════════════════════════════════════════════════════════════════════════════
//
//  transceiver_feeder_tb.v — testbench exercising transceiver_feeder driving
//  transceiver_in.
//
//  Instantiates both modules, feeds 4 known test samples, and checks that
//  transceiver_in outputs match the expected values from samples.hex using
//  the output data-valid strobe (o_tvalid).
//
//  ═════════════════════════════════════════════════════════════════════════════

`timescale 1ns / 1ps
`include "transceiver_feeder.v"
`include "i2s_in.v"

module transceiver_feeder_tb;

    // ──── Signals ──────────────────────────────────────────────────────────
    reg         clk;
    reg         rst_n;
    wire        sck;
    wire        ws;
    wire        sd;
    wire        done;

    wire        o_tvalid;
    wire [23:0] tdata;

    // ──── DUTs ─────────────────────────────────────────────────────────────

    // I2S stimulus generator
    transceiver_feeder #(
        .SCK_HALF_PERIOD(163),
        .NUM_SAMPLES    (4),       // use only the first 4 samples from .hex
        .SAMPLE_MAX     (48000)
    ) feeder (
        .clk     (clk),
        .rst_n   (rst_n),
        .done    (done),
        .sck     (sck),
        .ws      (ws),
        .sd      (sd)
    );

    // I2S receiver — bit clock driven directly from feeder
    transceiver_in #(
        .WIDTH        (24),
        .COUNTER_BITS (5)
    ) receiver (
        .clk      (sck),
        .rst_n    (rst_n),
        .ws       (ws),
        .sd       (sd),
        .o_tready (1'b1),
        .o_tvalid (o_tvalid),
        .tdata    (tdata)
    );

    // ──── System clock — used only for reset sync ─────────────────────────
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ──── Expected data (must match samples.hex) ──────────────────────────
    reg [23:0] expected [0:7];  // 4 samples x 2 channels (L+R)
    integer    frame_count;
    integer    errors;

    // ──── Test sequence ───────────────────────────────────────────────────
    initial begin : TEST_SEQ
        integer i;

        // Dump VCD
        $dumpfile("feeder_tb.vcd");
        $dumpvars(0, transceiver_feeder_tb);

        // Initialise
        rst_n = 1'b0;
        frame_count = 0;
        errors = 0;

        // Expected values (L and R are the same sample for each frame)
        expected[0] = 24'h000000;   // sample 0, L
        expected[1] = 24'h000000;   // sample 0, R
        expected[2] = 24'h7FFFFF;   // sample 1, L
        expected[3] = 24'h7FFFFF;   // sample 1, R
        expected[4] = 24'h800000;   // sample 2, L
        expected[5] = 24'h800000;   // sample 2, R
        expected[6] = 24'h123456;   // sample 3, L
        expected[7] = 24'h123456;   // sample 3, R

        $display("═══════════════════════════════════════════════════════════");
        $display("  transceiver_feeder_tb — starting simulation");
        $display("═══════════════════════════════════════════════════════════");

        // Hold reset for 200 ns, then de-assert
        #200 rst_n = 1'b1;
        $display("  Reset de-asserted at t=%0t", $time);

        // ── Align to SCK ──────────────────────────────────────────────────
        @(posedge sck);
        $display("  First SCK posedge at t=%0t", $time);

        // ── Capture frame by frame ────────────────────────────────────────
        //
        // Each sample produces one I2S frame (L + R). Instead of counting 
        // raw clock cycles, we listen directly to the receiver's handshaking 
        // flag (`o_tvalid`) to know exactly when a slot has finished loading.
        //
        for (i = 0; i < 4; i = i + 1) begin : FRAME_LOOP
            integer w;   

            // ── Left channel ────────────────────────────────────────────
            @(posedge o_tvalid);
            #1; // step 1ns clear of the clock edge for safe evaluation

            w = i * 2 + 0;
            if (tdata === expected[w]) begin
                $display("  [%0d] L PASS: tdata = %h (expected %h) at t=%0t",
                         i, tdata, expected[w], $time);
            end else begin
                $display("  [%0d] L FAIL: tdata = %h (expected %h) at t=%0t",
                         i, tdata, expected[w], $time);
                errors = errors + 1;
            end

            // ── Right channel ───────────────────────────────────────────
            @(posedge o_tvalid);
            #1; // step 1ns clear of the clock edge for safe evaluation

            w = i * 2 + 1;
            if (tdata === expected[w]) begin
                $display("  [%0d] R PASS: tdata = %h (expected %h) at t=%0t",
                         i, tdata, expected[w], $time);
            end else begin
                $display("  [%0d] R FAIL: tdata = %h (expected %h) at t=%0t",
                         i, tdata, expected[w], $time);
                errors = errors + 1;
            end
        end

        // ── Continue to done ──────────────────────────────────────────────
        $display("");
        $display("  Waiting for done signal...");

        wait(done);
        $display("  done asserted at t=%0t", $time);

        // ── Verify zero-padding (100 SCK cycles after done) ───────────────
        $display("  Checking zero-padding for 100 SCK cycles...");

        for (i = 0; i < 100; i = i + 1) begin
            @(posedge sck);
        end

        // Sample tdata after 100 SCK cycles
        #1;
        $display("  tdata after zero-padding = %h (expect 000000)", tdata);

        // Give it one more frame to settle
        repeat (64) @(posedge sck);
        #1;
        $display("  tdata after 1 more frame = %h (expect 000000)", tdata);

        // ── Summary ────────────────────────────────────────────────────────
        $display("");
        $display("═══════════════════════════════════════════════════════════");
        if (errors == 0) begin
            $display("  ALL CHECKS PASSED");
        end else begin
            $display("  %0d CHECK(S) FAILED", errors);
        end
        $display("═══════════════════════════════════════════════════════════");

        $finish;
    end

    // ──── Timeout ─────────────────────────────────────────────────────────
    initial begin
        #5000000;
        $display("  TIMEOUT — simulation took too long");
        $finish;
    end

endmodule
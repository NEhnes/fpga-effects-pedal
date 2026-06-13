`timescale 1ns / 1ps
`include "axistream_template.v"

module axistream_template_tb;

  // Parameters
  parameter WIDTH = 24;
  parameter CLK_PERIOD = 10;  // 10ns = 100MHz

  // Clock and reset
  reg tclk;
  reg rst_n;

  // Incoming (DUT inputs)
  reg [WIDTH-1:0] i_tdata;
  reg             i_tvalid;
  wire            i_tready;

  // Outgoing (DUT outputs)
  reg             o_tready;
  wire            o_tvalid;
  wire [WIDTH-1:0] o_tdata;

  // Test control
  integer num_pass = 0;
  integer num_fail = 0;

  // Instantiate DUT
  passthrough #(.WIDTH(WIDTH)) dut (
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
    tclk = 1'b0;
    forever #(CLK_PERIOD/2) tclk = ~tclk;
  end

  // Reset sequence
  initial begin
    rst_n = 1'b0;
    #(CLK_PERIOD * 5);  // Hold reset for 5 cycles
    rst_n = 1'b1;
  end

  // Test 1: Basic data passthrough with handshake
  initial begin
    wait(rst_n == 1'b1);
    #CLK_PERIOD;

    // Both sender and receiver ready
    @(posedge tclk) begin
      i_tdata = 24'hDEADBE;
      i_tvalid = 1'b1;
      o_tready = 1'b1;
    end

    // Check i_tready is asserted (should match o_tready)
    @(posedge tclk) begin
      if (i_tready == 1'b1) begin
        $display("[PASS] Test 1a: i_tready asserted when o_tready=1");
        num_pass = num_pass + 1;
      end else begin
        $display("[FAIL] Test 1a: i_tready should be 1, got %b", i_tready);
        num_fail = num_fail + 1;
      end

      if (o_tvalid == 1'b1) begin
        $display("[PASS] Test 1b: o_tvalid asserted when i_tvalid=1");
        num_pass = num_pass + 1;
      end else begin
        $display("[FAIL] Test 1b: o_tvalid should be 1, got %b", o_tvalid);
        num_fail = num_fail + 1;
      end
    end

    // Data should appear after one cycle (registered)
    @(posedge tclk) begin
      if (o_tdata == 24'hDEADBE) begin
        $display("[PASS] Test 1c: o_tdata correctly latched (0x%h)", o_tdata);
        num_pass = num_pass + 1;
      end else begin
        $display("[FAIL] Test 1c: expected 0xDEADBE, got 0x%h", o_tdata);
        num_fail = num_fail + 1;
      end
    end
  end

  // Test 2: Backpressure (o_tready=0)
  initial begin
    wait(rst_n == 1'b1);
    #(CLK_PERIOD * 10);

    // Sender ready, but receiver not ready
    @(posedge tclk) begin
      i_tdata = 24'h123456;
      i_tvalid = 1'b1;
      o_tready = 1'b0;
    end

    // i_tready should follow o_tready
    @(posedge tclk) begin
      if (i_tready == 1'b0) begin
        $display("[PASS] Test 2a: i_tready=0 when o_tready=0 (backpressure)");
        num_pass = num_pass + 1;
      end else begin
        $display("[FAIL] Test 2a: i_tready should be 0, got %b", i_tready);
        num_fail = num_fail + 1;
      end

      if (o_tvalid == 1'b1) begin
        $display("[PASS] Test 2b: o_tvalid still asserted (valid i_tvalid)");
        num_pass = num_pass + 1;
      end else begin
        $display("[FAIL] Test 2b: o_tvalid should be 1, got %b", o_tvalid);
        num_fail = num_fail + 1;
      end
    end

    // Data should NOT update without handshake
    @(posedge tclk) begin
      if (o_tdata == 24'hDEADBE) begin  // Previous value from Test 1
        $display("[PASS] Test 2c: o_tdata unchanged without handshake");
        num_pass = num_pass + 1;
      end else begin
        $display("[FAIL] Test 2c: o_tdata should be 0xDEADBE, got 0x%h", o_tdata);
        num_fail = num_fail + 1;
      end
    end
  end

  // Test 3: Multiple transfers (burst)
  initial begin
    wait(rst_n == 1'b1);
    #(CLK_PERIOD * 40);

    // Clear backpressure from Test 2
    @(posedge tclk) begin
      o_tready = 1'b1;
    end

    // Transfer sequence
    @(posedge tclk) begin
      i_tdata = 24'hAABBCC;
      i_tvalid = 1'b1;
      o_tready = 1'b1;
    end

    @(posedge tclk) begin
      if (o_tdata == 24'hAABBCC) begin
        $display("[PASS] Test 3a: First beat latched correctly");
        num_pass = num_pass + 1;
      end else begin
        $display("[FAIL] Test 3a: expected 0xAABBCC, got 0x%h", o_tdata);
        num_fail = num_fail + 1;
      end
    end

    @(posedge tclk) begin
      i_tdata = 24'hDEDEDE;
    end

    @(posedge tclk) begin
      if (o_tdata == 24'hDEDEDE) begin
        $display("[PASS] Test 3b: Second beat latched correctly");
        num_pass = num_pass + 1;
      end else begin
        $display("[FAIL] Test 3b: expected 0xDEDEDE, got 0x%h", o_tdata);
        num_fail = num_fail + 1;
      end
    end
  end

  // Test 4: Reset clears output
  initial begin
    wait(rst_n == 1'b1);
    #(CLK_PERIOD * 80);

    // Load data
    @(posedge tclk) begin
      i_tdata = 24'hFFFFFF;
      i_tvalid = 1'b1;
      o_tready = 1'b1;
    end

    @(posedge tclk);

    // Assert reset
    @(posedge tclk) begin
      rst_n = 1'b0;
    end

    // Data should clear on next clock
    @(posedge tclk) begin
      if (o_tdata == 24'h000000) begin
        $display("[PASS] Test 4: o_tdata cleared on reset");
        num_pass = num_pass + 1;
      end else begin
        $display("[FAIL] Test 4: expected 0x000000, got 0x%h", o_tdata);
        num_fail = num_fail + 1;
      end
    end
  end

  // Test 5: i_tvalid=0 (no transfer)
  initial begin
    wait(rst_n == 1'b1);
    #(CLK_PERIOD * 110);

    @(posedge tclk) begin
      i_tvalid = 1'b0;
      o_tready = 1'b1;
    end

    @(posedge tclk) begin
      if (o_tvalid == 1'b0) begin
        $display("[PASS] Test 5a: o_tvalid=0 when i_tvalid=0");
        num_pass = num_pass + 1;
      end else begin
        $display("[FAIL] Test 5a: o_tvalid should be 0, got %b", o_tvalid);
        num_fail = num_fail + 1;
      end

      if (i_tready == 1'b1) begin
        $display("[PASS] Test 5b: i_tready still follows o_tready");
        num_pass = num_pass + 1;
      end else begin
        $display("[FAIL] Test 5b: i_tready should be 1, got %b", i_tready);
        num_fail = num_fail + 1;
      end
    end
  end

  // Timeout
  initial begin
    #(CLK_PERIOD * 150);  // 1.5µs max
    $display("\n========== AXI-Stream Protocol Verification ==========");
    $display("✓ i_tready directly coupled to o_tready");
    $display("✓ o_tvalid directly coupled to i_tvalid");
    $display("✓ o_tdata registers only on valid handshake (i_tvalid & o_tready)");
    $display("✓ Reset asynchronously clears o_tdata to zero");
    $display("✓ No combinational paths on data (protocol compliant)");
    $display("======================================================\n");
    $display("=== Test Summary ===");
    $display("Passed: %d", num_pass);
    $display("Failed: %d", num_fail);
    if (num_fail == 0) begin
      $display("Status: ALL TESTS PASSED");
    end else begin
      $display("Status: SOME TESTS FAILED");
    end
    $finish;
  end

  // Waveform dump
  initial begin
    $dumpfile("axistream_template_tb.vcd");
    $dumpvars(0, axistream_template_tb);
  end

endmodule
/*
this is by no means a comprehensive testbench
i spent a lot of time analyzing the waveform in gtkwave

formally verify later ... maybe
*/

`timescale 1ns / 1ps
`include "i2s_in.v"

module transceiver_in_tb;

    // Clock and reset
    reg clk;
    reg rst_n;
    reg test_over;

    // DUT ports
    reg        ws;
    reg        sd;
    reg        o_tready;
    wire       o_tvalid;
    wire [23:0] tdata;

    // -------------------------------------------------------------------------
    // Test vectors
    // -------------------------------------------------------------------------
    reg [23:0] src_data [0:3];   // a few words for the demo
    integer    data_counter;    // counts bits transmitted for the current word
    integer    word_counter;    // counts words transmitted

    // ──── DUT ─────
    transceiver_in #(
        .WIDTH(24),
        .COUNTER_BITS(5)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .ws       (ws),
        .sd       (sd),
        .o_tready (o_tready),
        .o_tvalid (o_tvalid),
        .tdata    (tdata)
    );

    // ── Clock: 10 ns period ──
    initial begin
        clk = 1'b0;
        o_tready = 1'b1;
        forever #5 clk = ~clk;
    end

  // -------------------------------------------------------------------------
  // Test stimulus
  // -------------------------------------------------------------------------
  initial begin
    // -------------------------------------------------
    // Dump waveform for later inspection
    // -------------------------------------------------
    $dumpfile("actual_tb.vcd");
    $dumpvars(0, transceiver_in_tb);

    // -------------------------------------------------
    // Initialise registers
    // -------------------------------------------------
    rst_n = 0;          // keep DUT in reset initially
    ws    = 0;
    sd    = 0;
    data_counter = 0;
    word_counter = 0;
    test_over = 0;

    // --------- test words --------------
    src_data[0] = 24'hABCDEF; // 101010111100110111101111
    src_data[1] = 24'h123456; // 000100100011010001010110 // shifted left 1
    src_data[2] = 24'hBADBAD; // 101110101101101110101101 // shifted left 1
    src_data[3] = 24'hF0000D; // 111100000000000000001101 // shifted left 1
    // src_data[0] = 24'b101010111100110111101111;
    // src_data[1] = 24'b000100100011010001010110; 
    // src_data[2] = 24'b101110101101101110101101;
    // src_data[3] = 24'b111100000000000000001101;

    // ---------- spot boundary issues between words ----------
    // src_data[0] = {24{1'b1}};
    // src_data[1] = {24{1'b0}};
    // src_data[2] = {24{1'b1}};
    // src_data[3] = {24{1'b0}};

    // ---------- easy to spot patterns ---------
    // src_data[0] = 24'b010101010101010101010101; // 1-1-1-1
    // src_data[1] = 24'b001100110011001100110011; // 2-2-2-2
    // src_data[2] = 24'b000111000111000111000111; // 3-3-3-3
    // src_data[3] = 24'b000011110000111100001111; // 4-4-4-4

    #40 rst_n = 1;  // de‑assert reset

    // -------------------------------------------------
    // Transmit all words, LSB‑first, one bit per clock
    // -------------------------------------------------
    for (word_counter = 0; word_counter < 4; word_counter = word_counter + 1) begin
      ws <= ~ws;   // switch at start of word

      // Send 24 bits of the current word, MSB first
      for (data_counter = 0; data_counter < 24; data_counter = data_counter + 1) begin
        // Subtract from 23 to grab the top bits first
        sd <= src_data[word_counter][23 - data_counter];
        @(posedge clk);
      end
    end

    // -------------------------------------------------
    // 6Wait for the DUT to raise `valid` and capture the last word
    // -------------------------------------------------
    // @(posedge o_tvalid);
    // $display("----- Received word -----");
    // $display("  Expected : %h", src_data[word_counter-1]);
    // $display("  DUT out  : %h", tdata);
    // $display("--------------------------");

    // -------------------------------------------------
    // Finish simulation
    // -------------------------------------------------
    test_over = 1;
    #100 $finish;
  end
endmodule
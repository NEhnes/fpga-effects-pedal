/* TESTS TO ADD LATER

 * - data wraparound in fifo preserves correct element order (ptr and data behaviour)

 * - write when full is ignored (data not stored, pointer doesn't advance)
 * - read when empty is ignored (no data output, pointer doesn't advance)

 * - verify internal reset behaviour
 * - tvalid assertion/de-assertion
 * - AXI-Stream compliance rules (ALL)

 * - interleaved read/write in odd sequence
 * - varying read/write burst lengths
 * - extended read/write cycling
 * - empty->full verify every slot
 * - full->empty verify every slot

 * - do something to protect against no-power of 2 depths (throw error or some shit idfk

Edge Cases

Single-slot FIFO (DEPTH=1)
Power-of-2 boundaries (DEPTH=2, 4, 8, 16)
Maximum fill (all slots written, one read, all written again)
Simultaneous write and read from full FIFO
Simultaneous write and read from single-item FIFO
 */

`timescale 1ns / 1ps
`include "fifo_buffer.v"

module fifo_buffer_tb;

    // Parameters matching DUT
    localparam integer WIDTH = 24;
    localparam integer DEPTH = 8;

    // Clock and reset
    reg tclk;
    reg rst_n;

    // Test data for FIFO
    reg [WIDTH-1:0] test_mem [0:DEPTH-1];

    // DUT input signals
    reg [WIDTH-1:0] i_tdata;
    reg i_tvalid;
    wire i_tready;

    // DUT output signals
    wire [WIDTH-1:0] o_tdata;
    wire o_tvalid;
    reg o_tready;

    // Test control
    integer num_pass = 0;
    integer num_fail = 0;

    // DELAYED RECEIVE test control
    integer correct_responses = 0;
    integer total_responses = 4;

    // TREADY CHECK control
    reg tready_deassert_complete = 0;
    reg tready_assert_complete = 0;

    // Instantiate DUT
    fifo_buffer #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .tclk(tclk),
        .rst_n(rst_n),
        .i_tdata(i_tdata),
        .i_tvalid(i_tvalid),
        .i_tready(i_tready),
        .o_tdata(o_tdata),
        .o_tvalid(o_tvalid),
        .o_tready(o_tready)
    );

    // Clock generation: 10ns period
    initial begin
        tclk = 1'b0;
        forever #5 tclk = ~tclk;
    end

    initial begin

        // Waveform dump
        $dumpfile("fifo_buffer_tb.vcd");
        $dumpvars(0, fifo_buffer_tb);

        // Fill some test data
        test_mem[0] = {(WIDTH/4){4'hA}};
        test_mem[1] = {(WIDTH/4){4'hB}};
        test_mem[2] = {(WIDTH/4){4'hC}};
        test_mem[3] = {(WIDTH/4){4'hD}};

        reset;

        empty_read;

        reset;

        delayed_receive;

        reset;

        tready_check;

        reset;
    end

    // Timeout & summary
    initial begin
        #50000;  // 50µs max simulation time
        $display("\n========== Test Summary ==========");
        $display("Passed: %d", num_pass);
        $display("Failed: %d", num_fail);
        $display("==================================");
        $finish;
    end

    // Reset sequence
    task reset;
        begin
            rst_n = 1'b0;
            i_tdata = {WIDTH{1'b0}};
            i_tvalid = 1'b0;
            o_tready = 1'b0;
            #50;  // Hold reset for 5 clock cycles
            rst_n = 1'b1;
        end
    endtask

    /* =======================================
     *           DELAYED RECEIVE
     * Sends a burst of data
     * Waits
     * Accepts said burst of data
     * Compares against expected output
     * ======================================*/
    task delayed_receive;
        begin
            // open up input line
            i_tvalid = 1'b1;
            @(posedge tclk);

            // send input data
            for(integer i = 0; i < 4; i = i + 1) begin
                i_tdata = test_mem[i];
                if (i == 3) i_tvalid = 1'b0;
                @(posedge tclk);
            end

            // delay
            #100;

            // open up output line; delay to match pipeline output
            o_tready = 1'b1;
            @(posedge tclk);
            @(posedge tclk);
            @(posedge tclk);

            // check outcoming data
            for(integer i = 0; i < 4; i = i + 1) begin
                if (o_tdata == test_mem[i]) begin
                    correct_responses = correct_responses + 1;
                end else $display("expected data: %h | received data: %h", test_mem[i], o_tdata);
                @(posedge tclk);
            end

            // print pass/fail
            if (correct_responses == total_responses) begin
                $display("DELAYED RECEIVE - [PASS]");
                num_pass = num_pass + 1;
            end else begin
                $display("DELAYED RECEIVE - [FAIL]");
                num_fail = num_fail + 1;
            end
            
            #100;
        end
    endtask


    /* =======================================
     *             EMPTY READ
     * **Assumes the fifo mem register is empty
     * **Assumes reset just happened
     * Opens up output line
     * Check if data comes out or valid go high
     * ======================================*/
    task empty_read;
        begin
            o_tready = 1'b1;
            if (o_tvalid == 1'b1 || o_tdata != {WIDTH{1'b0}}) begin
                $display("EMPTY READ - [FAIL]");
                num_fail = num_fail + 1;
            end else begin
                $display("EMPTY READ - [PASS]");
                num_pass = num_pass + 1;
            end
        end
    endtask

    /* =======================================
     *              TREADY CHECK
     * Sends more data than depth
     * Checks for de-assertion when full (handshake)
     * Checks for re-assertion when !full (handshake)
     * ======================================*/
    task tready_check;
        begin
            i_tvalid = 1'b1;
            @(posedge tclk);

            // fill memory & check for de-assertion
            for (integer i = 0; i < DEPTH + 4; i = i + 1) begin
                i_tdata = test_mem[ i % 4 ];
                if (i_tready == 1'b0) begin
                    tready_deassert_complete = 1'b1;
                end
                @(posedge tclk);
            end

            // open up output line and check for re-assertion
            o_tready = 1'b1;
            @(posedge tclk);
            @(posedge tclk);
            if (i_tready == 1'b1) tready_assert_complete = 1'b1;

            @(posedge tclk);

            if (tready_assert_complete && tready_deassert_complete) begin
                $display("TREADY CHECK - [PASS]");
                num_pass = num_pass + 1;
            end else begin
                $display("TREADY CHECK - [FAIL]");
                num_fail = num_fail + 1;
            end
        end
    endtask

endmodule
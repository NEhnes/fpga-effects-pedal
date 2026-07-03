/*
 * fifo_buffer.v
 *
 * Single-clock AXI-Stream FIFO buffer for audio samples.
 *
 * Notes:
 * - This is a synchronous FIFO, not a clock-domain-crossing FIFO.
 * - Uses active-low asynchronous reset as implemented below.
 * - DEPTH parameter MUST be a power of 2 for pointer wrap to work as written
 * 
 * Key AXI-Stream compliance checklist:
 * - tclk, rst_n, tvalid, tready present on both ends                   YES
 * - tvalid not de-asserted until handshake                             YES
 * - tdata must not change until handshake                              YES
 * - data latched on posedge of clock                                   YES
 * - Handshake occurs when tready && tvalid                             YES
 * 
 * Things to check over
 * - Is it possible for read ptr to pass write ptr (shouldn't be)
 * - Verify combinational logic working on reset
 */

module fifo_buffer #(
    parameter integer WIDTH = 24,
    parameter integer DEPTH = 16
)(
    input  wire                 tclk,
    input  wire                 rst_n,

    input  wire [WIDTH-1:0]     i_tdata,
    input  wire                 i_tvalid,
    output wire                 i_tready,

    output wire [WIDTH-1:0]     o_tdata,
    output wire                 o_tvalid,
    input  wire                 o_tready
);

    localparam integer PTR_WIDTH = $clog2(DEPTH);

    reg [WIDTH-1:0]      fifo_mem         [0:DEPTH-1];
    reg [PTR_WIDTH-1:0]  wr_ptr, rd_ptr;
    reg [PTR_WIDTH:0]    fill_count;
    reg [WIDTH-1:0]      o_tdata_reg;
    reg                  o_tvalid_reg;

    wire full  = (fill_count == DEPTH);
    wire empty = (fill_count == 0);

    // for testing purposes
    wire [WIDTH-1:0] fifo_mem0 = fifo_mem[0];
    wire [WIDTH-1:0] fifo_mem1 = fifo_mem[1];
    wire [WIDTH-1:0] fifo_mem2 = fifo_mem[2];
    wire [WIDTH-1:0] fifo_mem3 = fifo_mem[3];

    wire write_en = i_tvalid && i_tready;
    wire read_en  = o_tvalid && o_tready && !empty;

    assign i_tready = !full;
    assign o_tdata  = o_tdata_reg;
    assign o_tvalid = o_tvalid_reg;

    always @(posedge tclk or negedge rst_n) begin

        // reset mode
        if (!rst_n) begin
            wr_ptr     <= {PTR_WIDTH{1'b0}};
            rd_ptr     <= {PTR_WIDTH{1'b0}};
            fill_count <= {(PTR_WIDTH+1){1'b0}};
            o_tvalid_reg <= 1'b0;
            o_tdata_reg <= {WIDTH{1'b0}};

        // normal operation
        end else begin

            // input
            if (write_en) begin
                // reads old data
                fifo_mem[wr_ptr] <= i_tdata;
                wr_ptr <= wr_ptr + 1'b1;
            end

            // output
            if (read_en) begin
                o_tdata_reg <= fifo_mem[rd_ptr];
                rd_ptr <= rd_ptr + 1'b1;
            end

            // update fill count and tvalid based on what happened
            // YES THIS IS FUCKING AXI-STREAM COMPLIANT BECAUSE HANDSHAKE IS IMPLIED THRU COMBINATIONAL LOGIC
            case ({(write_en), read_en})
                // write, no read
                2'b10: begin
                    fill_count <= fill_count + 1'b1;
                    o_tvalid_reg <= 1'b1;
                end
                // read, no write
                2'b01: begin
                    fill_count <= fill_count - 1'b1;
                    if (fill_count == 1) o_tvalid_reg <= 1'b0; // "empty" wire is a cycle behind so i must use this
                end
                // AND/NAND
                default: fill_count <= fill_count;
            endcase
        end
    end

endmodule
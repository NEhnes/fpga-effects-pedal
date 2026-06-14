module delay #(
    parameter WIDTH = 24,
    parameter DEPTH = 1024,
    parameter DELAY_CYCLES = 512
)(
    // === ADD EFFECT INPUTS HERE ===


    // ==============================


    input  wire        tclk,
    input  wire        rst_n,

    // Incoming
    input  wire [WIDTH-1:0] i_tdata,
    input  wire             i_tvalid,
    output wire             i_tready,

    // Outgoing
    input  wire             o_tready,
    output wire             o_tvalid,
    output reg  [WIDTH-1:0] o_tdata
);

// AXI-Stream handshake propagation
// this allows endpoints to effectively communicate together
// everything in the middle will be reliable on clock cycle, no axi logic needed
assign i_tready = o_tready;
assign o_tvalid = i_tvalid;


wire [WIDTH-1:0] processed;
assign processed = i_tdata;

// === ADD SUB-MODULE ASSIGNMENTS HERE ===
localparam integer PTR_WIDTH = $clog2(DEPTH);

reg [WIDTH-1:0]      ring_bufr   [0:DEPTH-1];
reg [PTR_WIDTH-1:0]  write_ptr;
reg [PTR_WIDTH-1:0]  read_ptr;
reg [PTR_WIDTH:0]    fill_count;

assign read_ptr = write_ptr - DELAY_CYCLES;

// ========================================

always @(posedge tclk or negedge rst_n) begin

    // clear bad data on reset
    if (!rst_n) begin
        o_tdata <= {WIDTH{1'b0}};
    end 
    
    else if (i_tvalid && o_tready) begin
        // register updates when send and receive are good
        o_tdata <= processed;
    end
end
endmodule

// ======= ADD SUB-MODULES HERES =======


// =====================================
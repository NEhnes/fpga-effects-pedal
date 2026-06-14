module pipeline #(
    parameter integer WIDTH = 24,
    parameter integer COUNTER_BITS = 5,
    parameter integer FIFO_DEPTH = 16,
    parameter [15:0] INPUT_GAIN = 16'h6000,
    parameter [15:0] NORMALIZED_CLIP = 16'h4000
)(
    input  wire             rst_n,
    input  wire             clk,
    input  wire             ws,
    input  wire             sd,

    input  wire             o_tready,
    output wire             o_tvalid,
    output wire [WIDTH-1:0] o_tdata
);

    wire              i2s_tvalid;
    wire [WIDTH-1:0]  i2s_tdata;
    wire              fifo_i_tready;

    wire              fifo_o_tvalid;
    wire [WIDTH-1:0]  fifo_o_tdata;
    wire              hard_clip_i_tready;

    transceiver_in #(
        .WIDTH(WIDTH),
        .COUNTER_BITS(COUNTER_BITS)
    ) u_i2s_transceiver_in (
        .rst_n(rst_n),
        .clk(clk),
        .ws(ws),
        .sd(sd),
        .o_tready(fifo_i_tready),
        .o_tvalid(i2s_tvalid),
        .tdata(i2s_tdata)
    );

    fifo_buffer #(
        .WIDTH(WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) u_fifo_buffer (
        .tclk(clk),
        .rst_n(rst_n),
        .i_tdata(i2s_tdata),
        .i_tvalid(i2s_tvalid),
        .i_tready(fifo_i_tready),
        .o_tdata(fifo_o_tdata),
        .o_tvalid(fifo_o_tvalid),
        .o_tready(hard_clip_i_tready)
    );

    hard_clip #(
        .WIDTH(WIDTH)
    ) u_hard_clip (
        ._input_gain(INPUT_GAIN),
        ._normalized_clip(NORMALIZED_CLIP),
        .tclk(clk),
        .rst_n(rst_n),
        .i_tdata(fifo_o_tdata),
        .i_tvalid(fifo_o_tvalid),
        .i_tready(hard_clip_i_tready),
        .o_tready(o_tready),
        .o_tvalid(o_tvalid),
        .o_tdata(o_tdata)
    );

endmodule

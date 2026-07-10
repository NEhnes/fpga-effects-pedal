module noise_gate #(
    parameter WIDTH = 24
)(
    input wire [15:0] threshold,
    input wire [15:0] attack,
    input wire [15:0] release_len,
    input signed [15:0] makeup_gain,
    input wire tclk,
    input wire rst_n,
    input wire [WIDTH-1:0] i_tdata,
    input wire i_tvalid,
    output wire i_tready,
    input wire o_tready,
    output wire o_tvalid,
    output reg [WIDTH-1:0] o_tdata
);
    reg signed [WIDTH-1:0] envelope;
    reg [15:0] gain_q114;

    wire signed [WIDTH-1:0] abs_sample = i_tdata[WIDTH-1] ? -$signed(i_tdata) : $signed(i_tdata);
    wire signed [WIDTH-1:0] leakage = envelope >>> 12;
    wire signed [WIDTH-1:0] next_envelope = (abs_sample > envelope) ? abs_sample : envelope - leakage;
    wire signed [WIDTH-1:0] scaled_threshold = $signed({1'b0, threshold}) <<< (WIDTH - 16);
    wire gate_open_now = (next_envelope > scaled_threshold);
    // sub_gain uses Q13, so unity is 0x2000 (not 0x4000).
    wire [31:0] attack_step = (attack == 0) ? 32'h2000 : (32'h2000 / attack);
    wire [31:0] release_step = (release_len == 0) ? 32'h2000 : (32'h2000 / release_len);
    wire [31:0] next_gain = gate_open_now
        ? ((gain_q114 + attack_step >= 32'h2000) ? 32'h2000 : gain_q114 + attack_step)
        : ((gain_q114 <= release_step) ? 32'd0 : gain_q114 - release_step);
    wire signed [WIDTH-1:0] gated;
    wire signed [WIDTH-1:0] makeup_applied;

    assign i_tready = o_tready;
    assign o_tvalid = i_tvalid;

    sub_gain #(.WIDTH(WIDTH)) gate_gain_stage (
        .i_sample(i_tdata), .gain_q114(gain_q114), .o_sample(gated)
    );
    sub_gain #(.WIDTH(WIDTH)) makeup_gain_stage (
        .i_sample(gated), .gain_q114(makeup_gain), .o_sample(makeup_applied)
    );

    always @(posedge tclk or negedge rst_n) begin
        if (!rst_n) begin
            o_tdata <= {WIDTH{1'b0}};
            envelope <= {WIDTH{1'b0}};
            gain_q114 <= 16'd0;
        end else if (i_tvalid && o_tready) begin
            o_tdata <= makeup_applied;
            envelope <= next_envelope;
            gain_q114 <= next_gain[15:0];
        end
    end
endmodule

module sub_gain #(
    parameter WIDTH = 24
)(
    input signed [WIDTH-1:0] i_sample,
    input signed [15:0] gain_q114,
    output signed [WIDTH-1:0] o_sample
);
    localparam FRAC_BITS = 13;
    wire signed [WIDTH+15:0] temp = i_sample * gain_q114;
    wire signed [WIDTH+15:0] shifted = (temp + (1 << (FRAC_BITS - 1))) >>> FRAC_BITS;
    localparam signed [WIDTH-1:0] MAX_VAL = {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] MIN_VAL = {1'b1, {(WIDTH-1){1'b0}}};
    assign o_sample = (shifted > MAX_VAL) ? MAX_VAL :
                      (shifted < MIN_VAL) ? MIN_VAL : shifted[WIDTH-1:0];
endmodule

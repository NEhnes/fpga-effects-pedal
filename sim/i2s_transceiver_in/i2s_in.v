module transceiver_in #(
    parameter WIDTH = 24,
    parameter COUNTER_BITS = 5    // 5 bits covers 0–24
)(
    // general state
    input  wire             rst_n,
    input  wire             clk, // doubles as sck

    // incoming
    input  wire             ws,
    input  wire             sd,

    // outgoing
    input wire              o_tready,
    output reg              o_tvalid,
    output reg  [WIDTH-1:0] tdata
);

reg r_ws, r_sd;
reg r_ws_last;
reg new_word_temp;

reg state; // 0 is idle, 1 is processing word

reg [COUNTER_BITS-1:0] word_counter;

reg [WIDTH-1:0] channel_1;
reg [WIDTH-1:0] channel_2;

always @(posedge clk) begin

    if (!rst_n) begin // reset logic
        o_tvalid     <= 1'b0;
        tdata        <= {WIDTH{1'b0}}; 

        r_sd         <= 1'b0;
        r_ws         <= ws;
        r_ws_last    <= ws;

        word_counter <= 5'b0;
        channel_1    <= 24'b0;
        channel_2    <= 24'b0;
        state        <= 1'b0;
    end 
    
    else begin
        // latch inputs (1 cycle delay) for stability
        r_ws <= ws;
        r_sd <= sd;

        // Handle AXI-S handshake backpressure
        // if (o_tready && o_tvalid) begin
        //     o_tvalid <= 1'b0; 
        // end

        // ── NEW WORD DETECTED (WS EDGE) ─────────
        if (r_ws_last != r_ws) begin
            r_ws_last    <= r_ws;
            word_counter <= 5'b1; // Reset counter, wait for NEXT cycle to sample MSB
            state        <= 1'b1;

            // write first data bit
            if (r_ws)
                channel_2[(WIDTH - 1)] <= r_sd;
            else
                channel_1[(WIDTH - 1)] <= r_sd;
            
            // Handle back-to-back I2S words safely (WS toggling exactly at word end)
            if (word_counter == (WIDTH - 1)) begin
                // o_tvalid <= 1'b1;
                // Reading old value of r_ws_last here correctly grabs the finished channel
                tdata    <= r_ws_last ? channel_2 : channel_1;
            end
        end
        // ── SHIFTING DATA ──
        else if (state != 0) begin // does not get entered
            if (word_counter == WIDTH) begin
                // o_tvalid <= 1'b1;
                $display("WORD END");
                state    <= 1'b0; // back to idle
                tdata    <= r_ws ? channel_2[23:0] : channel_1[23:0]; 
            end else begin // GETS ENABLED
                // Write to bit [WIDTH-1 - word_counter]
                if (r_ws)
                    channel_2[(WIDTH - 1) - word_counter] <= r_sd;
                else
                    channel_1[(WIDTH - 1) - word_counter] <= r_sd;
                
                word_counter <= word_counter + 1;

                // TEMPORARY VALID DE-ASSERTION FIX
                if(word_counter == 5) begin
                    o_tvalid <= 1'b0;
                end
            end
        end
    end
end
endmodule
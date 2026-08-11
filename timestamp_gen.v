module timestamp_gen (
    input  wire        clk,
    input  wire        rst_n,         // active-low reset
    input  wire        capture,       // pulse high for 1 cycle to latch a timestamp
    output reg  [15:0] free_running,  // the raw, ever-ticking counter (for visibility/debug)
    output reg  [15:0] timestamp_out  // the latched value attached to a record
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            free_running <= 16'd0;
        else
            free_running <= free_running + 1'b1;
    end

    // The capture register - holds whatever the counter's value was at the
    // moment "capture" was pulsed, until the next capture happens.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            timestamp_out <= 16'd0;
        else if (capture)
            timestamp_out <= free_running;
    end

endmodule

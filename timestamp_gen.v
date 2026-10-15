// timestamp_gen.v
//
// The hardware timestamp generator module of the data integrity engine.
// This is very close to the very first module built in this project
// (counter.v, Week 1) - just widened from 8 bits to 16 bits, and with
// one addition: a "capture" mechanism, so a specific timestamp value can
// be latched and held steady for a record, rather than the raw counter
// (which never stops ticking) being used directly.
//
// Two things happen here:
//   1. A 16-bit free-running counter ticks up every clock cycle, forever,
//      from the moment the FPGA powers on (this represents "hardware time").
//   2. When "capture" is pulsed high for one cycle, the CURRENT counter
//      value is latched into "timestamp_out" and held there - this is the
//      value that gets attached to a sensor record as it passes through
//      the integrity engine.

module timestamp_gen (
    input  wire        clk,
    input  wire        rst_n,         // active-low reset
    input  wire        capture,       // pulse high for 1 cycle to latch a timestamp
    output reg  [15:0] free_running,  // the raw, ever-ticking counter (for visibility/debug)
    output reg  [15:0] timestamp_out  // the latched value attached to a record
);

    // The free-running counter - identical mechanism to counter.v from Week 1,
    // just 16 bits wide instead of 8, so it can count much higher before
    // wrapping around (0 to 65,535 instead of 0 to 255).
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

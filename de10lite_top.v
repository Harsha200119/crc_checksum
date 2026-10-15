module de10lite_top (
    input  wire       clk,     // board's onboard 50 MHz oscillator
    input  wire       rst_n,   // wired to a board switch (e.g. SW0)
    input  wire       rx,      // wire to Arduino TX pin
    input  wire       key0_n,  // physical button KEY0, active-low: next byte
    input  wire       key1_n,  // physical button KEY1, active-low: previous byte
    output wire       LEDR0,   // heartbeat - blinks each time a record is processed
    output wire       LEDR1,   // status - on = valid, off = corrupted
    output wire [6:0] HEX0,    // 7-segment digit: low nibble of the CRC remainder
    output wire [6:0] HEX1,    // 7-segment digit: high nibble of the CRC remainder
    output wire [6:0] HEX4,    // 7-segment digit: low nibble of the selected record byte
    output wire [6:0] HEX5     // 7-segment digit: high nibble of the selected record
);

    wire [71:0] last_record;
    wire [15:0] audit_timestamp;
    wire        integrity_valid;
    wire [7:0]  crc_remainder;
    wire        result_ready;

    integrity_engine_top #(.CLKS_PER_BIT(5208)) u_engine (
        .clk             (clk),
        .rst_n           (rst_n),
        .rx              (rx),
        .last_record     (last_record),
        .audit_timestamp (audit_timestamp),
        .integrity_valid (integrity_valid),
        .crc_remainder   (crc_remainder),
        .result_ready    (result_ready)
    );

    // Heartbeat: a simple toggle flip-flop. Every time result_ready
    // pulses (once per fully-processed record), heartbeat flips state.
    reg heartbeat;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            heartbeat <= 1'b0;
        else if (result_ready)
            heartbeat <= ~heartbeat;
    end

    assign LEDR0 = heartbeat;
    assign LEDR1 = integrity_valid;

    // Split the 8-bit CRC remainder into two 4-bit hex digits and
    // decode each one to its 7-segment display pattern.
    seg7_decoder u_hex0 (.hex_in(crc_remainder[3:0]), .seg_out(HEX0));
    seg7_decoder u_hex1 (.hex_in(crc_remainder[7:4]), .seg_out(HEX1));

    // Let KEY0/KEY1 step through and view all 9 bytes of the record,
    // not just a fixed first byte.
    wire [7:0] selected_byte;
    wire [3:0] byte_index; // not displayed, but available if needed later

    byte_viewer u_viewer (
        .clk           (clk),
        .rst_n         (rst_n),
        .key0_n        (key0_n),
        .key1_n        (key1_n),
        .last_record   (last_record),
        .selected_byte (selected_byte),
        .byte_index    (byte_index)
    );

    seg7_decoder u_hex4 (.hex_in(selected_byte[3:0]), .seg_out(HEX4));
    seg7_decoder u_hex5 (.hex_in(selected_byte[7:4]), .seg_out(HEX5));

endmodule

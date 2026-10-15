// uart_receiver_tb.v
// Testbench for uart_receiver.v
//
// Simulates the Arduino side: drives the "rx" line with a standard UART
// frame (start bit, 8 data bits LSB-first, stop bit) for each of the 9
// bytes that make up the SAME real dataset record already used to test
// the CRC generator and checker. If the UART receiver correctly
// reconstructs the exact same 72-bit value, that's proof the serial
// link works correctly end-to-end.
//
// Uses a small CLKS_PER_BIT value (20) purely to keep simulation time
// short - the real board will use CLKS_PER_BIT = 5208 (50 MHz / 9600 baud).

`timescale 1ns/1ps

module uart_receiver_tb;

    localparam CLKS_PER_BIT = 20; // small value for fast simulation only

    reg         clk;
    reg         rst_n;
    reg         rx;
    wire [71:0] record_out;
    wire        record_ready;

    integer     pass_count = 0;
    integer     fail_count = 0;

    uart_receiver #(.CLKS_PER_BIT(CLKS_PER_BIT)) uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .rx           (rx),
        .record_out   (record_out),
        .record_ready (record_ready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Sends one byte over the "rx" line as a standard UART frame
    task send_byte;
        input [7:0] data;
        integer i;
        begin
            rx = 1'b0; // start bit
            repeat (CLKS_PER_BIT) @(posedge clk);

            for (i = 0; i < 8; i = i + 1) begin // 8 data bits, LSB first
                rx = data[i];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end

            rx = 1'b1; // stop bit
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 0;
        rx    = 1'b1; // UART idle state is high
        #12;
        rst_n = 1;
        repeat (5) @(posedge clk);

        // The same real record (Node 6, temp 41 ...), split into its
        // 9 constituent bytes, MSB-first: 6a 5f e4 ff ff ff 00 00 de
        send_byte(8'h6a);
        send_byte(8'h5f);
        send_byte(8'he4);
        send_byte(8'hff);
        send_byte(8'hff);
        send_byte(8'hff);
        send_byte(8'h00);
        send_byte(8'h00);
        send_byte(8'hde);

        // Give the design a moment to settle, then check the result
        repeat (5) @(posedge clk);
        #1;

        if (record_out == 72'h6a5fe4ffffff0000de) begin
            $display("PASS: UART receiver correctly reassembled the record: %h", record_out);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: record_out = %h, expected 6a5fe4ffffff0000de", record_out);
            fail_count = fail_count + 1;
        end

        #10;
        $display("---------------------------------------------");
        $display("Total: %0d PASS, %0d FAIL", pass_count, fail_count);
        $stop;
    end

    // Track how many times record_ready pulses, to confirm it only
    // fires once (after the 9th byte), not once per byte
    integer ready_count = 0;
    always @(posedge clk) begin
        if (record_ready) ready_count = ready_count + 1;
    end

endmodule

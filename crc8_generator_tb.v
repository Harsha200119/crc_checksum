// crc8_generator_tb.v
// Testbench for crc8_generator.v
//
// Runs two test cases:
//   1. All-zero data word -> trivial sanity check (CRC should be 0,
//      since the feedback XOR never triggers on all-zero input)
//   2. A REAL record from the project's dataset (Node ID=6, temp=41,
//      humidity=63, water_level=100, N=255, P=255, K=255, timestamp=0),
//      whose correct CRC was independently computed and verified in the
//      Python data_preparation.ipynb notebook (Section 4). Expected CRC:
//      8'b11011110. This cross-validates the hardware against the
//      already-validated software reference implementation.

`timescale 1ns/1ps

module crc8_generator_tb;

    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [63:0] data_word;
    wire        busy;
    wire        done;
    wire [7:0]  crc_out;

    integer     pass_count = 0;
    integer     fail_count = 0;

    crc8_generator uut (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .data_word (data_word),
        .busy      (busy),
        .done      (done),
        .crc_out   (crc_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Runs one test: loads data_word, pulses start, waits for done,
    // checks crc_out against expected, and reports PASS/FAIL.
    task run_test;
        input [63:0] test_data;
        input [7:0]  expected_crc;
        input [127:0] test_name; // just a label for the printout
        begin
            data_word = test_data;
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            wait (done == 1);

            if (crc_out === expected_crc) begin
                $display("PASS: %0s -> crc_out = %b (expected %b)", test_name, crc_out, expected_crc);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s -> crc_out = %b (expected %b)", test_name, crc_out, expected_crc);
                fail_count = fail_count + 1;
            end

            @(posedge clk); // let the FSM settle back to IDLE
        end
    endtask

    initial begin
        rst_n = 0;
        start = 0;
        data_word = 64'h0;
        #12;
        rst_n = 1;
        @(posedge clk);

        // Test 1: all-zero data word -> expect CRC = 0
        run_test(64'h0000000000000000, 8'b00000000, "All-zero data word");

        // Test 2: real dataset record (cross-validated against Python)
        run_test(64'b0110101001011111111001001111111111111111111111110000000000000000,
                  8'b11011110,
                  "Real record (Node 6, temp 41, cross-validated vs Python)");

        #10;
        $display("---------------------------------------------");
        $display("Total: %0d PASS, %0d FAIL", pass_count, fail_count);
        $stop;
    end

endmodule

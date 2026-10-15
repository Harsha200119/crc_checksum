// crc8_checker_tb.v
// Testbench for crc8_checker.v
//
// Runs two test cases, both built from the SAME real dataset record
// already used to validate crc8_generator.v and cross-checked in the
// Python notebook:
//   1. The genuine, intact record (data + its correct CRC) -> expect valid=1
//   2. The SAME record with one bit flipped in the data portion, but the
//      ORIGINAL (now-mismatched) CRC still attached -> expect valid=0
//
// This is exactly the detection scenario the whole project is built
// around: can the hardware tell the difference between these two records?

`timescale 1ns/1ps

module crc8_checker_tb;

    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [71:0] full_record;
    wire        busy;
    wire        done;
    wire        valid;
    wire [7:0]  remainder_out;

    integer     pass_count = 0;
    integer     fail_count = 0;

    crc8_checker uut (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .full_record   (full_record),
        .busy          (busy),
        .done          (done),
        .valid         (valid),
        .remainder_out (remainder_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task run_test;
        input [71:0]  test_record;
        input         expected_valid;
        input [127:0] test_name;
        begin
            full_record = test_record;
            @(posedge clk); #1;
            start = 1;
            @(posedge clk); #1;
            start = 0;

            wait (done == 1);
            #1;

            if (valid === expected_valid) begin
                $display("PASS: %0s -> valid = %b (remainder = %h)", test_name, valid, remainder_out);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s -> valid = %b, expected %b (remainder = %h)",
                           test_name, valid, expected_valid, remainder_out);
                fail_count = fail_count + 1;
            end

            @(posedge clk); #1;
        end
    endtask

    initial begin
        rst_n = 0;
        start = 0;
        full_record = 72'h0;
        #12;
        rst_n = 1;
        @(posedge clk); #1;

        // Test 1: the genuine, intact record - expect valid = 1
        run_test(72'b011010100101111111100100111111111111111111111111000000000000000011011110,
                  1'b1, "Intact record (Node 6, temp 41)");

        // Test 2: same record with one data bit flipped, original CRC kept -
        // expect valid = 0 (this is the corruption-detection scenario)
        run_test(72'b011010100111111111100100111111111111111111111111000000000000000011011110,
                  1'b0, "Corrupted record (1 bit flipped in data)");

        #10;
        $display("---------------------------------------------");
        $display("Total: %0d PASS, %0d FAIL", pass_count, fail_count);
        $stop;
    end

endmodule

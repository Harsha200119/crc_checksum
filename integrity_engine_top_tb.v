// integrity_engine_top_tb.v
// Testbench for integrity_engine_top.v
//
// This is the big one: simulates the Arduino sending TWO full records
// over serial - one intact, one corrupted - and confirms the complete
// pipeline (UART receive -> obfuscate -> de-obfuscate -> audit
// timestamp -> CRC check) produces the correct Valid/Corrupted result
// for each, using the exact same real dataset record (and its corrupted
// variant) already used throughout this project's individual module tests.

`timescale 1ns/1ps

module integrity_engine_top_tb;

    localparam CLKS_PER_BIT = 4; // small value purely for fast simulation

    reg  clk;
    reg  rst_n;
    reg  rx;

    wire [71:0] last_record;
    wire [15:0] audit_timestamp;
    wire        integrity_valid;
    wire        result_ready;

    integer pass_count = 0;
    integer fail_count = 0;

    integrity_engine_top #(.CLKS_PER_BIT(CLKS_PER_BIT)) uut (
        .clk             (clk),
        .rst_n           (rst_n),
        .rx              (rx),
        .last_record     (last_record),
        .audit_timestamp (audit_timestamp),
        .integrity_valid (integrity_valid),
        .result_ready    (result_ready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task send_byte;
        input [7:0] data;
        integer i;
        begin
            rx = 1'b0; // start bit
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = data[i];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            rx = 1'b1; // stop bit
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    task send_record;
        input [7:0] b0, b1, b2, b3, b4, b5, b6, b7, b8;
        begin
            send_byte(b0); send_byte(b1); send_byte(b2);
            send_byte(b3); send_byte(b4); send_byte(b5);
            send_byte(b6); send_byte(b7); send_byte(b8);
        end
    endtask

    task check_result;
        input         expected_valid;
        input [127:0] test_name;
        begin
            wait (result_ready == 1'b1);
            #1;
            if (integrity_valid === expected_valid) begin
                $display("PASS: %0s -> integrity_valid = %b, last_record = %h, audit_timestamp = %0d",
                           test_name, integrity_valid, last_record, audit_timestamp);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s -> integrity_valid = %b, expected %b",
                           test_name, integrity_valid, expected_valid);
                fail_count = fail_count + 1;
            end
            @(posedge clk); #1;
        end
    endtask

    initial begin
        rst_n = 0;
        rx    = 1'b1;
        #12;
        rst_n = 1;
        repeat (5) @(posedge clk);

        // Record 1: the genuine, intact record (Node 6, temp 41)
        // bytes: 6a 5f e4 ff ff ff 00 00 de
        send_record(8'h6a, 8'h5f, 8'he4, 8'hff, 8'hff, 8'hff, 8'h00, 8'h00, 8'hde);
        check_result(1'b1, "Intact record");

        // Record 2: same record with one data bit flipped (byte 1: 5f -> 7f),
        // original CRC kept - expect this to be flagged as corrupted
        // bytes: 6a 7f e4 ff ff ff 00 00 de
        send_record(8'h6a, 8'h7f, 8'he4, 8'hff, 8'hff, 8'hff, 8'h00, 8'h00, 8'hde);
        check_result(1'b0, "Corrupted record");

        #20;
        $display("---------------------------------------------");
        $display("Total: %0d PASS, %0d FAIL", pass_count, fail_count);
        $stop;
    end

endmodule

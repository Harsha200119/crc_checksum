// timestamp_gen_tb.v
// Testbench for timestamp_gen.v (FIXED VERSION)
//
// Fix note: the previous version read signal values immediately after
// @(posedge clk), which can race with the hardware's own nonblocking
// updates from that same clock edge. This version adds a small #1 delay
// after every @(posedge clk) before reading any value for comparison -
// standard practice to avoid exactly this race.

`timescale 1ns/1ps

module timestamp_gen_tb;

    reg         clk;
    reg         rst_n;
    reg         capture;
    wire [15:0] free_running;
    wire [15:0] timestamp_out;

    integer     pass_count = 0;
    integer     fail_count = 0;
    reg  [15:0] sample_a, sample_b;
    reg  [15:0] expected_capture_value;

    timestamp_gen uut (
        .clk           (clk),
        .rst_n         (rst_n),
        .capture       (capture),
        .free_running  (free_running),
        .timestamp_out (timestamp_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst_n   = 0;
        capture = 0;
        #12;
        rst_n = 1;

        // Let a few cycles pass, always settling with #1 after each edge
        repeat (5) begin
            @(posedge clk);
            #1;
        end

        // Check 1: confirm free_running is genuinely incrementing by exactly
        // 1 per clock cycle (robust check - doesn't depend on exact reset timing)
        sample_a = free_running;
        @(posedge clk); #1;
        sample_b = free_running;

        if (sample_b == sample_a + 1) begin
            $display("PASS: free_running incremented correctly (%0d -> %0d)", sample_a, sample_b);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: free_running went from %0d to %0d (expected +1)", sample_a, sample_b);
            fail_count = fail_count + 1;
        end

        // Check 2: pulse capture, confirm timestamp_out latches the value
        // free_running held just before the capturing edge
        expected_capture_value = free_running;
        capture = 1;
        @(posedge clk); #1;
        capture = 0;

        if (timestamp_out == expected_capture_value) begin
            $display("PASS: timestamp_out correctly captured %0d at the moment of the pulse", timestamp_out);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: timestamp_out = %0d, expected %0d", timestamp_out, expected_capture_value);
            fail_count = fail_count + 1;
        end

        // Check 3: let more cycles pass WITHOUT capturing again.
        // timestamp_out must stay frozen even though free_running keeps moving.
        repeat (10) begin
            @(posedge clk);
            #1;
        end

        if (timestamp_out == expected_capture_value) begin
            $display("PASS: timestamp_out held steady at %0d while free_running moved on to %0d",
                       timestamp_out, free_running);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: timestamp_out drifted to %0d, expected it to stay at %0d",
                       timestamp_out, expected_capture_value);
            fail_count = fail_count + 1;
        end

        #10;
        $display("---------------------------------------------");
        $display("Total: %0d PASS, %0d FAIL", pass_count, fail_count);
        $stop;
    end

    initial begin
        $display("Time\tCapture\tFree_running\tTimestamp_out");
        $monitor("%0t\t%b\t%0d\t\t%0d", $time, capture, free_running, timestamp_out);
    end

endmodule

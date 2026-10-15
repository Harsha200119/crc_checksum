// xor_obfuscator_tb.v
// Testbench for xor_obfuscator.v
//
// Tests two things:
//   1. Obfuscation actually changes the data (output != input) - proves
//      the masking is doing something, not silently passing data through
//   2. Running the SAME module a second time on the obfuscated output
//      recovers the EXACT original data - proves the masking is genuinely
//      reversible, which is the whole point of Objective 2
//
// Uses the same real dataset record (Node 6) already cross-validated
// with the CRC generator, so results stay traceable across modules.

`timescale 1ns/1ps

module xor_obfuscator_tb;

    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [63:0] data_in;
    wire        busy;
    wire        done;
    wire [63:0] data_out;

    integer     pass_count = 0;
    integer     fail_count = 0;
    reg  [63:0] original_data;
    reg  [63:0] obfuscated_data;

    xor_obfuscator uut (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .data_in  (data_in),
        .busy     (busy),
        .done     (done),
        .data_out (data_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task run_once;
        input  [63:0] in_val;
        output [63:0] out_val;
        begin
            data_in = in_val;
            @(posedge clk); #1;
            start = 1;
            @(posedge clk); #1;
            start = 0;
            wait (done == 1);
            #1;
            out_val = data_out;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        rst_n = 0;
        start = 0;
        data_in = 64'h0;
        #12;
        rst_n = 1;
        @(posedge clk); #1;

        // The real dataset record (Node 6, temp 41...) used earlier
        original_data = 64'b0110101001011111111001001111111111111111111111110000000000000000;

        // Step 1: obfuscate it
        run_once(original_data, obfuscated_data);

        if (obfuscated_data != original_data) begin
            $display("PASS: Obfuscation changed the data (original: %h, obfuscated: %h)",
                       original_data, obfuscated_data);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Obfuscated data is identical to original - masking had no effect");
            fail_count = fail_count + 1;
        end

        // Step 2: run the SAME module on the obfuscated data to reverse it
        begin : reverse_step
            reg [63:0] recovered_data;
            run_once(obfuscated_data, recovered_data);

            if (recovered_data == original_data) begin
                $display("PASS: De-obfuscation recovered the exact original data (%h)", recovered_data);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Recovered data = %h, expected original %h", recovered_data, original_data);
                fail_count = fail_count + 1;
            end
        end

        #10;
        $display("---------------------------------------------");
        $display("Total: %0d PASS, %0d FAIL", pass_count, fail_count);
        $stop;
    end

endmodule

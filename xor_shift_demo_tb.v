// xor_shift_demo_tb.v
// Testbench for xor_shift_demo.v
//
// Feeds in a small 4-bit pattern and prints the register after every
// clock tick, so you can trace the "shift, then maybe XOR" behaviour
// by hand alongside the simulation output.

`timescale 1ns/1ps

module xor_shift_demo_tb;

    reg        clk;
    reg        rst_n;
    reg        data_in;
    wire [3:0] reg_out;

    // A small test pattern, fed in MSB first.
    // Extended to 5 bits so the XOR feedback branch actually triggers
    // (with only 4 bits, reg_out[3] never becomes 1 before a shift happens).
    reg [4:0] test_bits = 5'b10110;
    integer   i;

    xor_shift_demo uut (
        .clk     (clk),
        .rst_n   (rst_n),
        .data_in (data_in),
        .reg_out (reg_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst_n   = 0;
        data_in = 0;
        #12;
        rst_n = 1;

        for (i = 4; i >= 0; i = i - 1) begin
            data_in = test_bits[i];
            @(posedge clk);
        end

        #5;
        $display("Final reg_out = %b", reg_out);
        $stop;
    end

    initial begin
        $display("Time\tData_in\tReg_out");
        $monitor("%0t\t%b\t%b", $time, data_in, reg_out);
    end

endmodule

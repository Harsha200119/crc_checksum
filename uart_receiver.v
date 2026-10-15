// uart_receiver.v
//
// The UART Receiver & Record Formatter module - "Module 1" in the system
// architecture diagram. This is the piece that lets the Arduino actually
// talk to the FPGA: it reconstructs your 72-bit record from the raw
// serial bitstream the Arduino sends over UART, one byte (9 bytes total)
// at a time.
//
// This file contains TWO modules:
//   1. uart_rx_byte  - receives a single byte over a standard UART frame
//                       (1 start bit, 8 data bits LSB-first, 1 stop bit)
//   2. uart_receiver  - the top-level module: uses uart_rx_byte repeatedly
//                       to collect 9 bytes, and assembles them into the
//                       full 72-bit record
//
// CLKS_PER_BIT sets how many FPGA clock cycles make up one UART bit
// period. For a real board at 50 MHz clock and 9600 baud:
//   50,000,000 / 9,600 = 5208 clock cycles per bit
// This is left as a parameter so the testbench can use a much smaller
// value for fast simulation, while synthesis for the real board uses
// the true value of 5208.
//
// UPDATE 1 (after first physical hardware test): a watchdog timeout was
// added to uart_rx_byte, so a stuck receiver recovers automatically
// instead of freezing the whole pipeline forever.
//
// UPDATE 2: the watchdog firing also resets the record-level byte
// counter in uart_receiver, so a glitch mid-record doesn't silently
// misassemble the next successful byte into the wrong position.
//
// UPDATE 3 (this version - the important correctness fix): added a
// 2-flip-flop SYNCHRONIZER on the incoming rx signal. Arduino's serial
// output and the FPGA's 50 MHz clock run on two completely independent,
// unrelated clocks. Feeding an external signal like this directly into
// clocked logic without synchronizing it first risks "metastability" -
// occasionally sampling the signal at the exact instant it is changing,
// resolving unpredictably to the wrong value. This was the root cause of
// the unexpected/garbage numbers observed during live testing (extra
// values on the HEX displays that should only ever show two fixed
// results). The synchronizer adds a small, fixed 2-clock-cycle delay
// (about 40 ns at 50 MHz) before the signal is used anywhere else in the
// logic - utterly negligible compared to a UART bit period (about 104
// microseconds at 9600 baud), but enough to let the signal settle safely
// before it is sampled.

// ---------------------------------------------------------------------
// Module 1: single-byte UART receiver (with synchronizer + watchdog)
// ---------------------------------------------------------------------
module uart_rx_byte #(
    parameter CLKS_PER_BIT = 5208
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,          // the raw serial line coming from Arduino
    output reg  [7:0] byte_out,
    output reg        byte_valid,  // pulses high for 1 cycle when byte_out is valid
    output reg        byte_timeout // pulses high for 1 cycle if the watchdog fired
);

    // ---- Synchronizer: 2 flip-flops between the raw external rx signal
    // and everything else in this module. Only rx_sync2 is ever used
    // below - the raw rx input itself is never read directly again.
    reg rx_sync1, rx_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1; // UART idle state is high
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end

    localparam IDLE    = 3'd0;
    localparam START   = 3'd1;
    localparam DATA    = 3'd2;
    localparam STOP    = 3'd3;
    localparam CLEANUP = 3'd4;

    // A full byte legitimately takes about 9.5 bit periods (0.5 for the
    // start-bit midpoint check, 8 for the data bits, 1 for the stop bit).
    // The watchdog gives generous headroom above that - if we are still
    // not done after 15 bit periods, something has gone wrong, and we
    // give up and reset rather than waiting forever.
    localparam integer WATCHDOG_LIMIT = CLKS_PER_BIT * 15;

    reg [2:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  byte_reg;
    reg [31:0] watchdog_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            clk_count      <= 16'd0;
            bit_index      <= 3'd0;
            byte_valid     <= 1'b0;
            byte_timeout   <= 1'b0;
            byte_out       <= 8'h00;
            byte_reg       <= 8'h00;
            watchdog_count <= 32'd0;
        end else begin

            byte_timeout <= 1'b0; // default low unless explicitly pulsed below

            // Watchdog: counts up every cycle we are NOT in IDLE. Reset to
            // zero whenever we are in IDLE (waiting is fine, no timeout
            // needed there - only mid-byte reception is time-bounded).
            if (state == IDLE)
                watchdog_count <= 32'd0;
            else
                watchdog_count <= watchdog_count + 1'b1;

            if (state != IDLE && watchdog_count >= WATCHDOG_LIMIT) begin
                // Stuck for far longer than a real byte should ever take -
                // give up on this byte, tell the record assembler about it,
                // and go back to waiting for a fresh start bit.
                state        <= IDLE;
                byte_valid   <= 1'b0;
                byte_timeout <= 1'b1;
            end else begin

                case (state)

                    // Wait for the (synchronized) line to drop low - that's
                    // the start bit beginning
                    IDLE: begin
                        byte_valid <= 1'b0;
                        clk_count  <= 16'd0;
                        bit_index  <= 3'd0;
                        if (rx_sync2 == 1'b0)
                            state <= START;
                    end

                    // Wait until the MIDDLE of the start bit, then confirm it's
                    // still low (guards against noise glitches being mistaken
                    // for a real start bit)
                    START: begin
                        if (clk_count == (CLKS_PER_BIT - 1) / 2) begin
                            if (rx_sync2 == 1'b0) begin
                                clk_count <= 16'd0;
                                state     <= DATA;
                            end else begin
                                state <= IDLE; // false alarm, go back to waiting
                            end
                        end else begin
                            clk_count <= clk_count + 1'b1;
                        end
                    end

                    // Sample each of the 8 data bits at the middle of its bit
                    // period, LSB first (standard UART bit order)
                    DATA: begin
                        if (clk_count < CLKS_PER_BIT - 1) begin
                            clk_count <= clk_count + 1'b1;
                        end else begin
                            clk_count <= 16'd0;
                            byte_reg[bit_index] <= rx_sync2;
                            if (bit_index < 3'd7) begin
                                bit_index <= bit_index + 1'b1;
                            end else begin
                                bit_index <= 3'd0;
                                state     <= STOP;
                            end
                        end
                    end

                    // Wait out the stop bit, then present the completed byte
                    STOP: begin
                        if (clk_count < CLKS_PER_BIT - 1) begin
                            clk_count <= clk_count + 1'b1;
                        end else begin
                            byte_out   <= byte_reg;
                            byte_valid <= 1'b1;
                            clk_count  <= 16'd0;
                            state      <= CLEANUP;
                        end
                    end

                    // One cycle to let byte_valid be seen, then back to IDLE
                    CLEANUP: begin
                        byte_valid <= 1'b0;
                        state      <= IDLE;
                    end

                    default: state <= IDLE;

                endcase
            end
        end
    end

endmodule


// ---------------------------------------------------------------------
// Module 2: top-level record assembler
// ---------------------------------------------------------------------
module uart_receiver #(
    parameter CLKS_PER_BIT = 5208
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        rx,            // serial line from Arduino
    output reg  [71:0] record_out,    // the assembled 72-bit record
    output reg          record_ready  // pulses high for 1 cycle when a full record is ready
);

    wire [7:0] byte_out;
    wire       byte_valid;
    wire       byte_timeout;
    reg  [3:0] byte_count; // counts 0..8 (9 bytes per record)

    uart_rx_byte #(.CLKS_PER_BIT(CLKS_PER_BIT)) rx_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .rx           (rx),
        .byte_out     (byte_out),
        .byte_valid   (byte_valid),
        .byte_timeout (byte_timeout)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            record_out   <= 72'h0;
            byte_count   <= 4'd0;
            record_ready <= 1'b0;
        end else begin
            record_ready <= 1'b0;

            if (byte_timeout) begin
                // A glitch broke byte reception mid-record. Whatever bytes
                // we had already assembled for this record are now unreliable
                // and incomplete - discard them by resetting the counter, so
                // the NEXT successfully received byte is correctly treated
                // as the start of a fresh record, not a continuation.
                byte_count <= 4'd0;
            end else if (byte_valid) begin
                // Shift the new byte in - after 9 shifts, the first byte
                // received ends up as the most-significant byte, matching
                // the MSB-first byte order used when the record was split
                // for transmission
                record_out <= {record_out[63:0], byte_out};

                if (byte_count == 4'd8) begin
                    byte_count   <= 4'd0;
                    record_ready <= 1'b1;
                end else begin
                    byte_count <= byte_count + 1'b1;
                end
            end
        end
    end

endmodule

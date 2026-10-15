// xor_obfuscator.v
//
// The reversible XOR obfuscation module (Objective 2). Applies a basic
// masking layer to a 64-bit data word using a fixed key. This is
// deliberately NOT encryption - it's explicitly designed to deter only
// casual tampering, not withstand deliberate cryptanalysis (see the
// dissertation's Introduction and Ethical Considerations for the
// reasoning behind this scope decision).
//
// Because XOR is its own inverse (A ^ K ^ K = A), this SAME module and
// SAME key are used for both obfuscating a record before storage/
// transmission, and de-obfuscating it again on the receiving side -
// there is no separate "reverse" module needed.
//
// This follows the same start/busy/done handshake pattern as
// crc8_generator.v and timestamp_gen.v, so all three modules will plug
// into the same top-level FSM the same way (Phase 4's remaining task).

module xor_obfuscator (
    input  wire        clk,
    input  wire        rst_n,     // active-low reset
    input  wire        start,     // pulse high for 1 cycle to begin
    input  wire [63:0] data_in,   // the 64-bit word to obfuscate (or de-obfuscate)
    output reg          busy,
    output reg          done,     // pulses high for 1 cycle when data_out is valid
    output reg  [63:0] data_out
);

    // Fixed 64-bit obfuscation key. An alternating bit pattern is used
    // here for clarity (easy to visually confirm in a waveform); any
    // fixed pattern works identically, since XOR masking's reversibility
    // does not depend on the key's specific value, only that the same
    // key is used both times.
    localparam [63:0] KEY = 64'hA5A5A5A5A5A5A5A5;

    localparam IDLE   = 1'b0;
    localparam FINISH = 1'b1;

    reg state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            busy     <= 1'b0;
            done     <= 1'b0;
            data_out <= 64'h0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        data_out <= data_in ^ KEY;  // the actual obfuscation step
                        busy     <= 1'b1;
                        state    <= FINISH;
                    end
                end

                FINISH: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

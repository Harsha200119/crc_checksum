module xor_obfuscator (
    input  wire        clk,
    input  wire        rst_n,     // active-low reset
    input  wire        start,     // pulse high for 1 cycle to begin
    input  wire [63:0] data_in,   // the 64-bit word to obfuscate (or de-obfuscate)
    output reg          busy,
    output reg          done,     // pulses high for 1 cycle when data_out is valid
    output reg  [63:0] data_out
);
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

// The CRC checker/verifier module - the module that actually produces
// the "is this record intact or corrupted?"
module crc8_checker (
    input  wire        clk,
    input  wire        rst_n,        // active-low reset
    input  wire        start,        // pulse high for 1 cycle to begin
    input  wire [71:0] full_record,  // 64-bit data word + 8-bit CRC, as received
    output reg          busy,
    output reg          done,        // pulses high for 1 cycle when result is valid
    output reg          valid,       // 1 = record intact, 0 = corrupted
    output reg  [7:0]  remainder_out // the raw remainder (0 = intact), for debug/visibility
);

    // Same generator polynomial as crc8_generator.v: x^8+x^7+x^4+x^2+x+1
    localparam [7:0] POLY = 8'h97;

    localparam IDLE   = 2'b00;
    localparam SHIFT   = 2'b01;
    localparam FINISH = 2'b10;

    reg [1:0]  state;
    reg [7:0]  crc_reg;
    reg [71:0] record_reg;
    reg [6:0]  bit_idx;   // counts 0 .. 71 (72 bits to process)

    wire feedback = crc_reg[7] ^ record_reg[71];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            crc_reg       <= 8'h00;
            record_reg    <= 72'h0;
            bit_idx       <= 7'd0;
            busy          <= 1'b0;
            done          <= 1'b0;
            valid         <= 1'b0;
            remainder_out <= 8'h00;
        end else begin
            case (state)

                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        record_reg <= full_record;
                        crc_reg    <= 8'h00;
                        bit_idx    <= 7'd0;
                        busy       <= 1'b1;
                        state      <= SHIFT;
                    end
                end

                SHIFT: begin
                    if (feedback)
                        crc_reg <= {crc_reg[6:0], 1'b0} ^ POLY;
                    else
                        crc_reg <= {crc_reg[6:0], 1'b0};

                    record_reg <= {record_reg[70:0], 1'b0};

                    if (bit_idx == 7'd71)
                        state <= FINISH;
                    else
                        bit_idx <= bit_idx + 1'b1;
                end

                FINISH: begin
                    remainder_out <= crc_reg;
                    valid         <= (crc_reg == 8'h00);  // zero remainder = intact
                    done          <= 1'b1;
                    busy          <= 1'b0;
                    state         <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule

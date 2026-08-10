module crc8_generator (
    input  wire        clk,
    input  wire        rst_n,      // active-low reset
    input  wire        start,      // pulse high for 1 cycle to begin
    input  wire [63:0] data_word,  // the 64-bit record to protect
    output reg         busy,       // high while computation is in progress
    output reg         done,       // pulses high for 1 cycle when crc_out is valid
    output reg  [7:0]  crc_out     // the resulting 8-bit CRC
);

    // Generator polynomial x^8+x^7+x^4+x^2+x+1, Koopman notation (implicit
    // leading x^8 term dropped): binary 1001_0111 = 0x97
    localparam [7:0] POLY = 8'h97;

    localparam IDLE   = 2'b00;
    localparam SHIFT   = 2'b01;
    localparam FINISH = 2'b10;

    reg [1:0]  state;
    reg [7:0]  crc_reg;
    reg [63:0] data_reg;
    reg [6:0]  bit_idx;   // counts 0 .. 63 (64 bits to process)

    wire feedback = crc_reg[7] ^ data_reg[63];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            crc_reg  <= 8'h00;
            data_reg <= 64'h0;
            bit_idx  <= 7'd0;
            busy     <= 1'b0;
            done     <= 1'b0;
            crc_out  <= 8'h00;
        end else begin
            case (state)

                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        data_reg <= data_word;
                        crc_reg  <= 8'h00;
                        bit_idx  <= 7'd0;
                        busy     <= 1'b1;
                        state    <= SHIFT;
                    end
                end

                SHIFT: begin
                    // Shift the CRC register left, bringing in nothing new
   
                    if (feedback)
                        crc_reg <= {crc_reg[6:0], 1'b0} ^ POLY;
                    else
                        crc_reg <= {crc_reg[6:0], 1'b0};

                    // Shift the data word left so the next MSB is ready
                    data_reg <= {data_reg[62:0], 1'b0};

                    if (bit_idx == 7'd63)
                        state <= FINISH;
                    else
                        bit_idx <= bit_idx + 1'b1;
                end

                FINISH: begin
                    crc_out <= crc_reg;
                    done    <= 1'b1;
                    busy    <= 1'b0;
                    state   <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule

module integrity_engine_top #(
    parameter CLKS_PER_BIT = 5208 // 50 MHz / 9600 baud for the real board;
                                   // override with a small value in simulation
)(
    input  wire        clk,
    input  wire        rst_n,           // active-low reset
    input  wire        rx,              // serial line from Arduino
    output reg  [71:0] last_record,     // the most recently received record
    output reg  [15:0] audit_timestamp, // when the FPGA verified it
    output reg          integrity_valid, // 1 = intact, 0 = corrupted
    output reg  [7:0]  crc_remainder,   // the raw CRC checker remainder (00 = intact)
    output reg          result_ready     // pulses high for 1 cycle when a full
                                         // receive-verify cycle has completed
);

    // ---------------- Sub-module signals ----------------

    wire [71:0] uart_record;
    wire        uart_record_ready;

    reg         obf_start;
    reg  [63:0] obf_data_in;
    wire        obf_done;
    wire [63:0] obf_data_out;

    reg         ts_capture;
    wire [15:0] ts_timestamp_out;

    reg         chk_start;
    reg  [71:0] chk_full_record;
    wire        chk_done;
    wire        chk_valid;
    wire [7:0]  chk_remainder;

    // ---------------- Sub-module instances ----------------

    uart_receiver #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart (
        .clk          (clk),
        .rst_n        (rst_n),
        .rx           (rx),
        .record_out   (uart_record),
        .record_ready (uart_record_ready)
    );

    xor_obfuscator u_xor (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (obf_start),
        .data_in  (obf_data_in),
        .busy     (),
        .done     (obf_done),
        .data_out (obf_data_out)
    );

    timestamp_gen u_ts (
        .clk           (clk),
        .rst_n         (rst_n),
        .capture       (ts_capture),
        .free_running  (),
        .timestamp_out (ts_timestamp_out)
    );

    crc8_checker u_chk (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (chk_start),
        .full_record   (chk_full_record),
        .busy          (),
        .done          (chk_done),
        .valid         (chk_valid),
        .remainder_out (chk_remainder)
    );

    // ---------------- Top-level FSM ----------------

    localparam S_IDLE        = 4'd0;
    localparam S_OBF1_START  = 4'd1;
    localparam S_OBF1_WAIT   = 4'd2;
    localparam S_OBF2_START  = 4'd3;
    localparam S_OBF2_WAIT   = 4'd4;
    localparam S_TS_CAPTURE  = 4'd5;
    localparam S_TS_SETTLE   = 4'd6;
    localparam S_CHK_START   = 4'd7;
    localparam S_CHK_WAIT    = 4'd8;
    localparam S_DONE        = 4'd9;

    reg [3:0]  state;
    reg [71:0] received_record;   // the raw record as received over UART
    reg [7:0]  received_crc;      // its CRC field, held aside during (de)obfuscation
    reg [63:0] obfuscated_data;   // result after the first (obfuscate) pass
    reg [63:0] recovered_data;    // result after the second (de-obfuscate) pass

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            last_record     <= 72'h0;
            audit_timestamp <= 16'h0;
            integrity_valid <= 1'b0;
            crc_remainder   <= 8'h0;
            result_ready    <= 1'b0;
            obf_start       <= 1'b0;
            obf_data_in     <= 64'h0;
            ts_capture      <= 1'b0;
            chk_start       <= 1'b0;
            chk_full_record <= 72'h0;
            received_record <= 72'h0;
            received_crc    <= 8'h0;
            obfuscated_data <= 64'h0;
            recovered_data  <= 64'h0;
        end else begin
            // Default (pulsed) signals go low unless explicitly set below
            obf_start    <= 1'b0;
            ts_capture   <= 1'b0;
            chk_start    <= 1'b0;
            result_ready <= 1'b0;

            case (state)

                S_IDLE: begin
                    if (uart_record_ready) begin
                        received_record <= uart_record;
                        received_crc    <= uart_record[7:0];
                        state           <= S_OBF1_START;
                    end
                end

                S_OBF1_START: begin
                    obf_data_in <= received_record[71:8]; // the 64-bit data portion
                    obf_start   <= 1'b1;
                    state       <= S_OBF1_WAIT;
                end

                S_OBF1_WAIT: begin
                    if (obf_done) begin
                        obfuscated_data <= obf_data_out;
                        state           <= S_OBF2_START;
                    end
                end

                S_OBF2_START: begin
                    obf_data_in <= obfuscated_data; // run the same module again to reverse it
                    obf_start   <= 1'b1;
                    state       <= S_OBF2_WAIT;
                end

                S_OBF2_WAIT: begin
                    if (obf_done) begin
                        recovered_data <= obf_data_out; // should equal the original data
                        state          <= S_TS_CAPTURE;
                    end
                end

                S_TS_CAPTURE: begin
                    ts_capture <= 1'b1;
                    state      <= S_TS_SETTLE;
                end

                S_TS_SETTLE: begin
                    audit_timestamp <= ts_timestamp_out;
                    state           <= S_CHK_START;
                end

                S_CHK_START: begin
                    chk_full_record <= {recovered_data, received_crc};
                    chk_start       <= 1'b1;
                    state           <= S_CHK_WAIT;
                end

                S_CHK_WAIT: begin
                    if (chk_done) begin
                        integrity_valid <= chk_valid;
                        crc_remainder   <= chk_remainder;
                        last_record     <= received_record;
                        state           <= S_DONE;
                    end
                end

                S_DONE: begin
                    result_ready <= 1'b1;
                    state        <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule

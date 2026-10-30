module packet_transmitter(
    input wire clk,
    input wire reset,
    input wire [7:0] data_in,
    input wire pulse_transmit_cmd,
    input wire [7:0] transmit_cmd,
    input wire [15:0] payload_length,
    input wire tx_busy,

    output reg awaiting_payload,
    output reg uart_tx_en,
    output reg [7:0] uart_tx_data
);

localparam FSM_IDLE           = 3'd0;
localparam FSM_HEADER1        = 3'd1;
localparam FSM_HEADER2        = 3'd2;
localparam FSM_COMMAND        = 3'd3;
localparam FSM_LENGTH_LOW     = 3'd4;
localparam FSM_LENGTH_HIGH    = 3'd5;
localparam FSM_PAYLOAD        = 3'd6;
localparam FSM_CHECKSUM       = 3'd7;

reg [2:0] fsm_state = FSM_IDLE;
reg [7:0] transmit_cmd_latch;
reg [15:0] payload_length_latch;
reg [15:0] payload_count;
reg [7:0] checksum_calc;
reg checksum_sent;

wire tx_accept = uart_tx_en && !tx_busy;

always @(*) begin
    uart_tx_en = 1'b0;
    uart_tx_data = 8'd0;
    awaiting_payload = 1'b0;

    if (!tx_busy) begin
        case (fsm_state)
            FSM_HEADER1: begin
                uart_tx_en = 1'b1;
                uart_tx_data = 8'hA5;
            end
            FSM_HEADER2: begin
                uart_tx_en = 1'b1;
                uart_tx_data = 8'h5A;
            end
            FSM_COMMAND: begin
                uart_tx_en = 1'b1;
                uart_tx_data = transmit_cmd_latch;
            end
            FSM_LENGTH_LOW: begin
                uart_tx_en = 1'b1;
                uart_tx_data = payload_length_latch[7:0];
            end
            FSM_LENGTH_HIGH: begin
                uart_tx_en = 1'b1;
                uart_tx_data = payload_length_latch[15:8];
            end
            FSM_PAYLOAD: begin
                if (payload_count < payload_length_latch) begin
                    uart_tx_en = 1'b1;
                    awaiting_payload = 1'b1;
                    uart_tx_data = data_in;
                end
            end
            FSM_CHECKSUM: begin
                if (!checksum_sent) begin
                    uart_tx_en = 1'b1;
                    uart_tx_data = checksum_calc;
                end
            end
            default: ;
        endcase
    end
end

always @(posedge clk) begin
    if (reset) begin
        fsm_state <= FSM_IDLE;
        transmit_cmd_latch <= 8'd0;
        payload_length_latch <= 16'd0;
        payload_count <= 16'd0;
        checksum_calc <= 8'd0;
        checksum_sent <= 1'b0;
    end else begin
        case (fsm_state)
            FSM_IDLE: begin
                if (pulse_transmit_cmd && !tx_busy) begin
                    transmit_cmd_latch <= transmit_cmd;
                    payload_length_latch <= payload_length;
                    payload_count <= 16'd0;
                    checksum_calc <= 8'd0;
                    checksum_sent <= 1'b0;
                    fsm_state <= FSM_HEADER1;
                end
            end
            FSM_HEADER1: begin
                if (tx_accept)
                    fsm_state <= FSM_HEADER2;
            end
            FSM_HEADER2: begin
                if (tx_accept)
                    fsm_state <= FSM_COMMAND;
            end
            FSM_COMMAND: begin
                if (tx_accept) begin
                    checksum_calc <= checksum_calc ^ transmit_cmd_latch;
                    fsm_state <= FSM_LENGTH_LOW;
                end
            end
            FSM_LENGTH_LOW: begin
                if (tx_accept) begin
                    checksum_calc <= checksum_calc ^ payload_length_latch[7:0];
                    fsm_state <= FSM_LENGTH_HIGH;
                end
            end
            FSM_LENGTH_HIGH: begin
                if (tx_accept) begin
                    checksum_calc <= checksum_calc ^ payload_length_latch[15:8];
                    if (payload_length_latch == 16'd0)
                        fsm_state <= FSM_CHECKSUM;
                    else
                        fsm_state <= FSM_PAYLOAD;
                end
            end
            FSM_PAYLOAD: begin
                if (tx_accept) begin
                    checksum_calc <= checksum_calc ^ data_in;
                    payload_count <= payload_count + 1'b1;
                end else if ((payload_count == payload_length_latch) && !tx_busy) begin
                    // The last payload byte has completed on the UART line.
                    fsm_state <= FSM_CHECKSUM;
                end
            end
            FSM_CHECKSUM: begin
                if (tx_accept)
                    checksum_sent <= 1'b1;
                else if (checksum_sent && !tx_busy)
                    fsm_state <= FSM_IDLE;
            end
            default: fsm_state <= FSM_IDLE;
        endcase
    end
end

endmodule

module packet_receiver #(
    parameter MAX_PAYLOAD = 256
)(
    input wire clk,
    input wire reset,
    input wire byte_received,
    input wire [7:0] data_in,
    input wire valid_cmd,

    output reg [7:0] cmd,
    output reg [15:0] payload_length,
    output wire write_to_fifo_en,
    output reg end_of_packet,
    output reg packet_valid
);

localparam FSM_WAIT_SYNC1       = 3'd0;
localparam FSM_WAIT_SYNC2       = 3'd1;
localparam FSM_COMMAND          = 3'd2;
localparam FSM_COMMAND_VALIDATE = 3'd3;
localparam FSM_LENGTH_LOW       = 3'd4;
localparam FSM_LENGTH_HIGH      = 3'd5;
localparam FSM_PAYLOAD          = 3'd6;
localparam FSM_CHECKSUM         = 3'd7;

reg [2:0] fsm_state = FSM_WAIT_SYNC1;
reg [2:0] n_fsm_state;
reg [15:0] payload_count;
reg [7:0] checksum_calc;
reg payload_supported;

wire sync_byte_1 = data_in == 8'hA5;
wire sync_byte_2 = data_in == 8'h5A;

assign write_to_fifo_en = !reset && byte_received &&
                           (fsm_state == FSM_PAYLOAD) && payload_supported;

always @(*) begin
    n_fsm_state = fsm_state;
    case (fsm_state)
        FSM_WAIT_SYNC1: begin
            if (byte_received)
                n_fsm_state = sync_byte_1 ? FSM_WAIT_SYNC2 : FSM_WAIT_SYNC1;
        end
        FSM_WAIT_SYNC2: begin
            if (byte_received) begin
                n_fsm_state = sync_byte_2 ? FSM_COMMAND :
                              (sync_byte_1 ? FSM_WAIT_SYNC2 : FSM_WAIT_SYNC1);
            end
        end
        FSM_COMMAND: begin
            if (byte_received)
                n_fsm_state = FSM_COMMAND_VALIDATE;
        end
        FSM_COMMAND_VALIDATE:
            n_fsm_state = valid_cmd ? FSM_LENGTH_LOW : FSM_WAIT_SYNC1;
        FSM_LENGTH_LOW: begin
            if (byte_received)
                n_fsm_state = FSM_LENGTH_HIGH;
        end
        FSM_LENGTH_HIGH: begin
            if (byte_received) begin
                if ({data_in, payload_length[7:0]} == 16'd0)
                    n_fsm_state = FSM_CHECKSUM;
                else
                    n_fsm_state = FSM_PAYLOAD;
            end
        end
        FSM_PAYLOAD: begin
            if (byte_received && (payload_count == payload_length - 1'b1))
                n_fsm_state = FSM_CHECKSUM;
        end
        FSM_CHECKSUM: begin
            if (byte_received)
                n_fsm_state = FSM_WAIT_SYNC1;
        end
        default: n_fsm_state = FSM_WAIT_SYNC1;
    endcase
end

always @(posedge clk) begin
    if (reset) begin
        fsm_state <= FSM_WAIT_SYNC1;
        cmd <= 8'd0;
        payload_length <= 16'd0;
        payload_count <= 16'd0;
        checksum_calc <= 8'd0;
        payload_supported <= 1'b0;
        end_of_packet <= 1'b0;
        packet_valid <= 1'b0;
    end else begin
        fsm_state <= n_fsm_state;
        end_of_packet <= 1'b0;
        packet_valid <= 1'b0;

        if (byte_received &&
            (fsm_state == FSM_COMMAND || fsm_state == FSM_LENGTH_LOW ||
             fsm_state == FSM_LENGTH_HIGH || fsm_state == FSM_PAYLOAD))
            checksum_calc <= checksum_calc ^ data_in;

        case (fsm_state)
            FSM_WAIT_SYNC1: begin
                if (byte_received && sync_byte_1) begin
                    checksum_calc <= 8'd0;
                    payload_supported <= 1'b0;
                end
            end
            FSM_WAIT_SYNC2: begin
                if (byte_received && sync_byte_1) begin
                    checksum_calc <= 8'd0;
                    payload_supported <= 1'b0;
                end
            end
            FSM_COMMAND: begin
                if (byte_received)
                    cmd <= data_in;
            end
            FSM_LENGTH_LOW: begin
                if (byte_received)
                    payload_length[7:0] <= data_in;
            end
            FSM_LENGTH_HIGH: begin
                if (byte_received) begin
                    payload_length[15:8] <= data_in;
                    payload_count <= 16'd0;
                    payload_supported <= ({data_in, payload_length[7:0]} <= MAX_PAYLOAD);
                end
            end
            FSM_PAYLOAD: begin
                if (byte_received)
                    payload_count <= payload_count + 1'b1;
            end
            FSM_CHECKSUM: begin
                if (byte_received) begin
                    end_of_packet <= 1'b1;
                    if ((checksum_calc == data_in) && payload_supported)
                        packet_valid <= 1'b1;
                end
            end
            default: ;
        endcase
    end
end

endmodule

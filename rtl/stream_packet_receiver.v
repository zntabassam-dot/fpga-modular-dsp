// Receives framed audio blocks while a stream session is active.
// Audio payload bytes are staged here until the packet checksum is verified.
module stream_packet_receiver #(
    parameter MAX_PAYLOAD = 2048
)(
    input wire clk,
    input wire reset,
    input wire enable,
    input wire byte_received,
    input wire [7:0] data_in,
    input wire payload_copy_active,

    output reg payload_available,
    output reg [15:0] payload_length,
    input wire payload_consumed,
    input wire [$clog2(MAX_PAYLOAD)-1:0] payload_read_address,
    input wire payload_read_enable,
    output reg [7:0] payload_read_data,
    output reg payload_read_valid,

    output reg stop_received,
    output reg packet_error
);

localparam CMD_AUDIO_BLOCK = 8'h11;
localparam CMD_STOP_STREAM = 8'h12;

localparam RX_SYNC1    = 3'd0;
localparam RX_SYNC2    = 3'd1;
localparam RX_COMMAND  = 3'd2;
localparam RX_LENGTH_LO= 3'd3;
localparam RX_LENGTH_HI= 3'd4;
localparam RX_PAYLOAD  = 3'd5;
localparam RX_CHECKSUM = 3'd6;

reg [2:0] state;
reg [7:0] command;
reg [15:0] payload_count;
reg [7:0] checksum;
reg supported_packet;
reg audio_packet;
reg [7:0] packet_memory [0:MAX_PAYLOAD-1];

wire sync1 = (data_in == 8'hA5);
wire sync2 = (data_in == 8'h5A);
wire [15:0] received_length = {data_in, payload_length[7:0]};

always @(posedge clk) begin
    if (reset || !enable) begin
        state <= RX_SYNC1;
        command <= 8'd0;
        payload_length <= 16'd0;
        payload_count <= 16'd0;
        checksum <= 8'd0;
        supported_packet <= 1'b0;
        audio_packet <= 1'b0;
        payload_available <= 1'b0;
        payload_read_data <= 8'd0;
        payload_read_valid <= 1'b0;
        stop_received <= 1'b0;
        packet_error <= 1'b0;
    end else begin
        payload_read_valid <= payload_read_enable;
        stop_received <= 1'b0;
        packet_error <= 1'b0;

        if (payload_read_enable)
            payload_read_data <= packet_memory[payload_read_address];

        if (payload_consumed)
            payload_available <= 1'b0;

        case (state)
            RX_SYNC1: begin
                if (byte_received && sync1)
                    state <= RX_SYNC2;
            end

            RX_SYNC2: begin
                if (byte_received) begin
                    if (sync2)
                        state <= RX_COMMAND;
                    else
                        state <= sync1 ? RX_SYNC2 : RX_SYNC1;
                end
            end

            RX_COMMAND: begin
                if (byte_received) begin
                    command <= data_in;
                    checksum <= data_in;
                    state <= RX_LENGTH_LO;
                end
            end

            RX_LENGTH_LO: begin
                if (byte_received) begin
                    payload_length[7:0] <= data_in;
                    checksum <= checksum ^ data_in;
                    state <= RX_LENGTH_HI;
                end
            end

            RX_LENGTH_HI: begin
                if (byte_received) begin
                    payload_length[15:8] <= data_in;
                    checksum <= checksum ^ data_in;
                    payload_count <= 16'd0;
                    audio_packet <= (command == CMD_AUDIO_BLOCK);
                    // A new block may arrive while the prior validated block
                    // is being copied. This is safe while that one-byte-per-
                    // clock copy is active: it stays ahead of UART writes.
                    supported_packet <=
                        ((command == CMD_AUDIO_BLOCK) &&
                         (received_length >= 16'd2) &&
                         (received_length <= MAX_PAYLOAD) &&
                         !received_length[0] &&
                         (!payload_available || payload_copy_active)) ||
                        ((command == CMD_STOP_STREAM) &&
                         (received_length == 16'd0));

                    if (received_length == 16'd0)
                        state <= RX_CHECKSUM;
                    else if ((command == CMD_AUDIO_BLOCK) &&
                             (received_length <= MAX_PAYLOAD))
                        state <= RX_PAYLOAD;
                    else begin
                        // Consume unsupported payload bytes without storing them.
                        state <= RX_PAYLOAD;
                        supported_packet <= 1'b0;
                    end
                end
            end

            RX_PAYLOAD: begin
                if (byte_received) begin
                    checksum <= checksum ^ data_in;
                    if (audio_packet && supported_packet)
                        packet_memory[payload_count[$clog2(MAX_PAYLOAD)-1:0]] <= data_in;

                    payload_count <= payload_count + 1'b1;
                    if (payload_count == payload_length - 1'b1)
                        state <= RX_CHECKSUM;
                end
            end

            RX_CHECKSUM: begin
                if (byte_received) begin
                    state <= RX_SYNC1;
                    if (checksum == data_in) begin
                        if (supported_packet && audio_packet) begin
                            payload_available <= 1'b1;
                        end else if (supported_packet && command == CMD_STOP_STREAM) begin
                            stop_received <= 1'b1;
                        end else if (audio_packet || command == CMD_STOP_STREAM) begin
                            packet_error <= 1'b1;
                        end
                    end else if (audio_packet || command == CMD_STOP_STREAM) begin
                        packet_error <= 1'b1;
                    end
                end
            end

            default: state <= RX_SYNC1;
        endcase
    end
end

endmodule

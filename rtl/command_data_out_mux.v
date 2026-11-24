module command_data_out_mux(
    input wire active_echo,
    input wire active_fir_filter,
    input wire active_stream,
    input wire [15:0] legacy_payload_length,

    input wire [7:0] transmit_cmd_echo,
    input wire [7:0] transmit_cmd_fir_filter,
    input wire [7:0] transmit_cmd_stream,
    input wire read_next_fifo_pulse_echo,
    input wire read_next_fifo_pulse_fir_filter,
    input wire [7:0] transmission_payload_echo,
    input wire [7:0] transmission_payload_fir_filter,
    input wire [7:0] transmission_payload_stream,
    input wire [15:0] stream_payload_length,

    output reg [7:0] transmit_cmd,
    output reg read_next_fifo_pulse,
    output reg [7:0] transmission_payload,
    output reg [15:0] transmit_payload_length
);

always @(*) begin
    transmit_cmd = 8'd0;
    read_next_fifo_pulse = 1'b0;
    transmission_payload = 8'd0;
    transmit_payload_length = legacy_payload_length;

    if (active_stream) begin
        transmit_cmd = transmit_cmd_stream;
        transmission_payload = transmission_payload_stream;
        transmit_payload_length = stream_payload_length;
    end else if (active_echo) begin
        transmit_cmd = transmit_cmd_echo;
        read_next_fifo_pulse = read_next_fifo_pulse_echo;
        transmission_payload = transmission_payload_echo;
    end else if (active_fir_filter) begin
        transmit_cmd = transmit_cmd_fir_filter;
        read_next_fifo_pulse = read_next_fifo_pulse_fir_filter;
        transmission_payload = transmission_payload_fir_filter;
    end
end

endmodule

module command_data_in_mux(
    input wire clk,
    input wire reset,
    input wire awaiting_payload,
    input wire packet_tx_done,
    input wire echo_start,
    input wire fir_filter_start,
    input wire stream_session_active,
    input wire stream_session_done,

    output reg awaiting_payload_echo,
    output reg awaiting_payload_fir_filter,
    output reg awaiting_payload_stream,
    output reg active_echo,
    output reg active_fir_filter,
    output reg active_stream
);

// Remember which command owns the response until the packet is finished.
always @(posedge clk) begin
    if (reset) begin
        active_echo <= 1'b0;
        active_fir_filter <= 1'b0;
        active_stream <= 1'b0;
    end else begin
        if (stream_session_done)
            active_stream <= 1'b0;
        else if (stream_session_active)
            active_stream <= 1'b1;

        if (stream_session_active) begin
            active_echo <= 1'b0;
            active_fir_filter <= 1'b0;
        end else if (packet_tx_done) begin
            active_echo <= 1'b0;
            active_fir_filter <= 1'b0;
        end else if (echo_start) begin
            active_echo <= 1'b1;
            active_fir_filter <= 1'b0;
        end else if (fir_filter_start) begin
            active_echo <= 1'b0;
            active_fir_filter <= 1'b1;
        end
    end
end

// Forward each payload request only to the active command.
always @(*) begin
    awaiting_payload_echo = awaiting_payload && active_echo;
    awaiting_payload_fir_filter = awaiting_payload && active_fir_filter;
    awaiting_payload_stream = awaiting_payload && active_stream;
end

endmodule

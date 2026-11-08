module command_data_in_mux(
    input wire clk,
    input wire reset,
    input wire awaiting_payload,
    input wire packet_tx_done,
    input wire echo_start,
    input wire fir_filter_3tap_start,

    output reg awaiting_payload_echo,
    output reg awaiting_payload_fir_3tap,
    output reg active_echo,
    output reg active_fir_3tap
);

// Remember which command owns the response until the packet is finished.
always @(posedge clk) begin
    if (reset || packet_tx_done) begin
        active_echo <= 1'b0;
        active_fir_3tap <= 1'b0;
    end else if (echo_start) begin
        active_echo <= 1'b1;
        active_fir_3tap <= 1'b0;
    end else if (fir_filter_3tap_start) begin
        active_echo <= 1'b0;
        active_fir_3tap <= 1'b1;
    end
end

// Forward each payload request only to the active command.
always @(*) begin
    awaiting_payload_echo = awaiting_payload && active_echo;
    awaiting_payload_fir_3tap = awaiting_payload && active_fir_3tap;
end

endmodule

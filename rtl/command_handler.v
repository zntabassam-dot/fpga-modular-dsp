module command_handler(
    input wire clk,
    input wire reset,
    input wire [7:0] receive_cmd,
    input wire [7:0] transmit_cmd,
    input wire end_of_packet,
    input wire packet_valid,

    output reg valid_receive_cmd,
    output wire pulse_transmit_cmd,
    output reg echo_start
);

localparam CMD_ECHO = 8'h01;
localparam CMD_DATA = 8'hFF;

always @(*) begin
    valid_receive_cmd = (receive_cmd == CMD_ECHO);
end

assign pulse_transmit_cmd = (transmit_cmd == CMD_DATA);

always @(posedge clk) begin
    if (reset) begin
        echo_start <= 1'b0;
    end else begin
        echo_start <= end_of_packet && packet_valid &&
                      (receive_cmd == CMD_ECHO);
    end
end

endmodule

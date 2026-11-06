module command_handler(
    input wire clk,
    input wire reset,
    input wire [7:0] receive_cmd,
    input wire [7:0] transmit_cmd,
    input wire end_of_packet,
    input wire packet_valid,

    output reg valid_receive_cmd,
    output wire pulse_transmit_cmd,
    output reg echo_start,
    output reg is_first_packet_in_array,
    output reg fir_filter_3tap_start
);

localparam CMD_ECHO = 8'h01;
localparam CMD_FIR_FIRST_PACKET = 8'h02;
localparam CMD_FIR_NON_FIRST_PACKET = 8'h03;
localparam CMD_DATA = 8'hFF;

// Receive-side commands (PC > FPGA)
always @(*) begin
    valid_receive_cmd = 0;
    is_first_packet_in_array = 0;

    case (receive_cmd)
        CMD_ECHO                    : begin
            valid_receive_cmd = 1;
        end
        CMD_FIR_FIRST_PACKET        : begin
            valid_receive_cmd = 1;
            is_first_packet_in_array = 1;
        end
        CMD_FIR_NON_FIRST_PACKET    : begin
            valid_receive_cmd = 1;
            is_first_packet_in_array = 0;
        end
    endcase
end

// Transmit-side commands (FPGA > PC)
assign pulse_transmit_cmd = (transmit_cmd == CMD_DATA);


always @(posedge clk) begin
    if (reset) begin
        echo_start <= 1'b0;
        fir_filter_3tap_start <= 1'b0;
    end else begin
        echo_start <= end_of_packet && packet_valid && (receive_cmd == CMD_ECHO);
        fir_filter_3tap_start <= end_of_packet && packet_valid && ((receive_cmd == CMD_FIR_FIRST_PACKET) || (receive_cmd == CMD_FIR_NON_FIRST_PACKET));
    end
end

endmodule

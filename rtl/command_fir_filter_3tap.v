module command_fir_filter_3tap(
    input wire clk,
    input wire reset,
    input wire is_first_packet_in_array,
    input wire fir_filter_3tap_start,
    input wire awaiting_payload_fir_3tap,
    input wire [7:0] data_from_fifo,

    output reg [7:0] transmit_cmd,
    output wire read_next_fifo_pulse,
    output wire [7:0] data_out
);

localparam CMD_DATA = 8'hFF;

assign transmit_cmd = 8'b0;
assign read_next_fifo_pulse = 1'b0;
assign data_out = 8'b0;


endmodule

module command_fir_filter_3tap(
    input wire clk,
    input wire reset,
    input wire is_first_packet_in_array,
    input wire fir_filter_3tap_start,
    input wire awaiting_payload,
    input wire [7:0] data_from_fifo,

    output reg [7:0] transmit_cmd,
    output wire read_next_fifo_pulse,
    output wire [7:0] data_out
);

localparam CMD_DATA = 8'hFF;


endmodule

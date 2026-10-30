module command_echo(
    input wire clk,
    input wire reset,
    input wire echo_start,
    input wire awaiting_payload,
    input wire [7:0] data_from_fifo,

    output reg [7:0] transmit_cmd,
    output wire read_next_fifo_pulse,
    output wire [7:0] data_out
);

localparam CMD_DATA = 8'hFF;

// The FIFO holds its registered head byte on data_from_fifo. The transmitter
// samples that byte on the same edge that this enable advances the FIFO.
assign data_out = data_from_fifo;
assign read_next_fifo_pulse = awaiting_payload;

always @(posedge clk) begin
    if (reset)
        transmit_cmd <= 8'd0;
    else if (echo_start)
        transmit_cmd <= CMD_DATA;
    else
        transmit_cmd <= 8'd0;
end

endmodule

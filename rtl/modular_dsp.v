module modular_dsp(

    input               clk     , // Top level system clock input.
    input   wire        BTN1    ,
    input   wire        uart_rxd, // UART Recieve pin.
    output  wire        uart_txd // UART transmit pin.

);

// Clock frequency in hertz.
parameter CLK_HZ = 12000000;
parameter BIT_RATE = 1_500_000;
parameter PAYLOAD_BITS = 8;
parameter POWERUP_RESET_CYCLES = 32768;

// BTN1 is high while pressed: pressing asserts reset, releasing runs the design.
reg [15:0] powerup_counter = 16'd0;
wire powerup_reset = powerup_counter < POWERUP_RESET_CYCLES;

always @(posedge clk) begin
    if (powerup_reset)
        powerup_counter <= powerup_counter + 1'b1;
end

wire reset = BTN1 || powerup_reset;
wire resetn = ~reset;

// ------------------------------------------------------------------------- 

//
// UART RX module.
//
wire [PAYLOAD_BITS-1:0]  uart_rx_data;
wire        uart_rx_valid;
wire        uart_rx_break;
//
uart_rx #(
.BIT_RATE(BIT_RATE),
.PAYLOAD_BITS(PAYLOAD_BITS),
.CLK_HZ  (CLK_HZ  )
) i_uart_rx(
.clk          (clk          ), // Top level system clock input.
.resetn       (resetn       ), // Asynchronous active low reset.
.uart_rxd     (uart_rxd     ), // UART Recieve pin.
.uart_rx_en   (1'b1         ), // Recieve enable
.uart_rx_break(uart_rx_break), // Did we get a BREAK message?
.uart_rx_valid(uart_rx_valid), // Valid data recieved and available.
.uart_rx_data (uart_rx_data )  // The recieved data.
);

//
// UART TX module.
//
wire        uart_tx_busy;
wire [PAYLOAD_BITS-1:0]  uart_tx_data;
wire        uart_tx_en;
//
uart_tx #(
.BIT_RATE(BIT_RATE),
.PAYLOAD_BITS(PAYLOAD_BITS),
.CLK_HZ  (CLK_HZ  )
) i_uart_tx(
.clk          (clk              ),
.resetn       (resetn           ),
.uart_txd     (uart_txd         ),
.uart_tx_en   (uart_tx_en),
.uart_tx_busy (uart_tx_busy     ),
.uart_tx_data (uart_tx_data     )
);

//
// Buffer - Primary FIFO
//

wire fifo_empty;
wire fifo_full;
wire [7:0] data_out_fifo;
wire [11:0] fifo_count;
wire write_to_fifo_en;
wire read_next_fifo_pulse;
wire stream_control_fifo_read;
wire end_of_packet;
wire full_packet_valid;
wire stream_active;
wire fifo_reset = reset || (end_of_packet && !full_packet_valid);
//
buffer #(.DEPTH(2048)) fifo(
.clk            (clk                ),
.write_enable   (write_to_fifo_en  ),
.data_in        (uart_rx_data       ),
.read_enable    (read_next_fifo_pulse || stream_control_fifo_read),
.reset          (fifo_reset         ),

.data_out       (data_out_fifo      ),
.empty          (fifo_empty         ),
.full           (fifo_full          ),
.count          (fifo_count         )
);

//
// Packet Receiver
//
wire valid_incoming_cmd;

wire [7:0] receive_cmd;
wire [15:0] payload_length;

//
packet_receiver #(.MAX_PAYLOAD(2048)) packet_receiver(
.clk                    (clk            ),
.reset                  (reset          ),
.byte_received          (uart_rx_valid && !stream_active),
.data_in                (uart_rx_data   ),
.valid_cmd              (valid_incoming_cmd),

.cmd                    (receive_cmd    ),
.payload_length         (payload_length ),
.write_to_fifo_en       (write_to_fifo_en),
.end_of_packet          (end_of_packet  ),
.packet_valid           (full_packet_valid)      
);

//
// Packet Transmitter
//
wire pulse_transmit_cmd;
wire [7:0] transmit_cmd;
wire awaiting_payload;
wire [7:0] transmission_payload;
wire [15:0] transmit_payload_length;
wire packet_tx_done;
//
packet_transmitter packet_transmitter(
.clk                    (clk                ),
.reset                  (reset              ),
.data_in                (transmission_payload),
.pulse_transmit_cmd     (pulse_transmit_cmd ),
.transmit_cmd           (transmit_cmd       ),
.payload_length         (transmit_payload_length),
.tx_busy                (uart_tx_busy       ),

.awaiting_payload       (awaiting_payload   ),
.uart_tx_en             (uart_tx_en         ),
.uart_tx_data           (uart_tx_data       ),
.packet_tx_done         (packet_tx_done     )
);


//
// Command Handler
//
wire echo_start;
wire is_first_packet_in_array;
wire fir_filter_start;
wire load_stream_coefficients;
wire start_audio_stream;
//
command_handler command_handler(
.clk                    (clk            ),
.reset                  (reset          ),
.receive_cmd            (receive_cmd    ),
.transmit_cmd           (transmit_cmd   ),
.end_of_packet          (end_of_packet  ),
.packet_valid           (full_packet_valid),

.valid_receive_cmd      (valid_incoming_cmd),
.pulse_transmit_cmd     (pulse_transmit_cmd),
.echo_start             (echo_start     ),
.is_first_packet_in_array(is_first_packet_in_array),
.fir_filter_start       (fir_filter_start),
.load_stream_coefficients(load_stream_coefficients),
.start_audio_stream     (start_audio_stream)
);

//
// Command Data In Mux
// Mux - Select currently active command to accept data (via awaiting_payload)
//
wire awaiting_payload_echo;
wire awaiting_payload_fir_filter;
wire awaiting_payload_stream;
wire active_echo;
wire active_fir_filter;
wire active_stream;
wire stream_session_done;
wire [7:0] transmit_cmd_stream;
wire [7:0] transmission_payload_stream;
wire [15:0] stream_payload_length;
wire [7:0] transmit_cmd_echo;
wire read_next_fifo_pulse_echo;
wire [7:0] transmission_payload_echo;
wire [7:0] transmit_cmd_fir_filter;
wire read_next_fifo_pulse_fir_filter;
wire [7:0] transmission_payload_fir_filter;
//
command_data_in_mux command_data_in_mux(
.clk                    (clk                ),
.reset                  (reset              ),
.awaiting_payload       (awaiting_payload   ),
.packet_tx_done         (packet_tx_done     ),
.echo_start             (echo_start         ),
.fir_filter_start       (fir_filter_start),
.stream_session_active  (stream_active),
.stream_session_done    (stream_session_done),

.awaiting_payload_echo  (awaiting_payload_echo),
.awaiting_payload_fir_filter(awaiting_payload_fir_filter),
.awaiting_payload_stream(awaiting_payload_stream),
.active_echo             (active_echo),
.active_fir_filter       (active_fir_filter),
.active_stream           (active_stream)
);

//
// Command Data Out Mux
// Mux - Prevent multiple inactive commands from actively driving the same output
//
command_data_out_mux command_data_out_mux(
.active_echo                    (active_echo),
.active_fir_filter              (active_fir_filter),
.active_stream                  (active_stream),
.legacy_payload_length          (payload_length),
.transmit_cmd_echo              (transmit_cmd_echo),
.transmit_cmd_fir_filter        (transmit_cmd_fir_filter),
.transmit_cmd_stream            (transmit_cmd_stream),
.read_next_fifo_pulse_echo      (read_next_fifo_pulse_echo),
.read_next_fifo_pulse_fir_filter(read_next_fifo_pulse_fir_filter),
.transmission_payload_echo      (transmission_payload_echo),
.transmission_payload_fir_filter(transmission_payload_fir_filter),
.transmission_payload_stream    (transmission_payload_stream),
.stream_payload_length          (stream_payload_length),

.transmit_cmd                   (transmit_cmd),
.read_next_fifo_pulse           (read_next_fifo_pulse),
.transmission_payload           (transmission_payload),
.transmit_payload_length        (transmit_payload_length)
);

//
// COMMAND - Echo
//
//
command_echo command_echo(
.clk                    (clk                ),
.reset                  (reset              ),
.echo_start             (echo_start         ),
.awaiting_payload_echo  (awaiting_payload_echo),
.data_from_fifo         (data_out_fifo      ),

.transmit_cmd           (transmit_cmd_echo       ),
.read_next_fifo_pulse   (read_next_fifo_pulse_echo),
.data_out               (transmission_payload_echo)
);

//
// COMMAND - 41-tap FIR low-pass filter
//

command_fir_filter command_fir_filter(
.clk                    (clk                ),
.reset                  (reset              ),
.is_first_packet_in_array(is_first_packet_in_array),
.fir_filter_start       (fir_filter_start),
.awaiting_payload_fir_filter(awaiting_payload_fir_filter),
.payload_length         (payload_length     ),
.data_from_fifo         (data_out_fifo      ),

.transmit_cmd           (transmit_cmd_fir_filter),
.read_next_fifo_pulse   (read_next_fifo_pulse_fir_filter),
.data_out               (transmission_payload_fir_filter)
);

audio_stream_controller audio_stream_controller(
.clk                        (clk),
.reset                      (reset),
.load_coefficients_start    (load_stream_coefficients),
.start_stream_request       (start_audio_stream),
.legacy_payload_length      (payload_length),
.legacy_fifo_data           (data_out_fifo),
.legacy_fifo_read_enable    (stream_control_fifo_read),
.uart_rx_valid              (uart_rx_valid),
.uart_rx_data               (uart_rx_data),
.stream_active              (stream_active),
.awaiting_payload           (awaiting_payload_stream),
.packet_tx_done             (packet_tx_done),
.transmit_cmd               (transmit_cmd_stream),
.transmit_payload_length    (stream_payload_length),
.transmission_payload       (transmission_payload_stream),
.stream_session_done        (stream_session_done)
);



endmodule

module modular_dsp(

    input               clk     , // Top level system clock input.
    input   wire        BTN1    ,
    input   wire        uart_rxd, // UART Recieve pin.
    output  wire        uart_txd // UART transmit pin.

);

// Clock frequency in hertz.
parameter CLK_HZ = 12000000;
parameter BIT_RATE =   500000;
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
wire write_to_fifo_en;
wire read_next_fifo_pulse;
wire end_of_packet;
wire full_packet_valid;
wire fifo_reset = reset || (end_of_packet && !full_packet_valid);
//
buffer #(.DEPTH(2048)) fifo(
.clk            (clk                ),
.write_enable   (write_to_fifo_en  ),
.data_in        (uart_rx_data       ),
.read_enable    (read_next_fifo_pulse),
.reset          (fifo_reset         ),

.data_out       (data_out_fifo      ),
.empty          (fifo_empty         ),
.full           (fifo_full          )  
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
.byte_received          (uart_rx_valid  ),
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
wire packet_tx_done;
//
packet_transmitter packet_transmitter(
.clk                    (clk                ),
.reset                  (reset              ),
.data_in                (transmission_payload),
.pulse_transmit_cmd     (pulse_transmit_cmd ),
.transmit_cmd           (transmit_cmd       ),
.payload_length         (payload_length     ),
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
wire fir_filter_3tap_start;
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
.fir_filter_3tap_start  (fir_filter_3tap_start)
);

//
// Command Data In Mux
// Mux - Select currently active command to accept data (via awaiting_payload)
//
wire awaiting_payload_echo;
wire awaiting_payload_fir_3tap;
wire active_echo;
wire active_fir_3tap;
//
command_data_in_mux command_data_in_mux(
.clk                    (clk                ),
.reset                  (reset              ),
.awaiting_payload       (awaiting_payload   ),
.packet_tx_done         (packet_tx_done     ),
.echo_start             (echo_start         ),
.fir_filter_3tap_start  (fir_filter_3tap_start),

.awaiting_payload_echo  (awaiting_payload_echo),
.awaiting_payload_fir_3tap  (awaiting_payload_fir_3tap),
.active_echo             (active_echo),
.active_fir_3tap         (active_fir_3tap)
);

//
// Command Data Out Mux
// Mux - Prevent multiple inactive commands from actively driving the same output
//
command_data_out_mux command_data_out_mux(
.active_echo                    (active_echo),
.active_fir_3tap                (active_fir_3tap),
.transmit_cmd_echo              (transmit_cmd_echo),
.transmit_cmd_fir_3tap          (transmit_cmd_fir_3tap),
.read_next_fifo_pulse_echo      (read_next_fifo_pulse_echo),
.read_next_fifo_pulse_fir_3tap  (read_next_fifo_pulse_fir_3tap),
.transmission_payload_echo      (transmission_payload_echo),
.transmission_payload_fir_3tap  (transmission_payload_fir_3tap),

.transmit_cmd                   (transmit_cmd),
.read_next_fifo_pulse           (read_next_fifo_pulse),
.transmission_payload           (transmission_payload)
);

//
// COMMAND - Echo
//
wire [7:0] transmit_cmd_echo;
wire read_next_fifo_pulse_echo;
wire [7:0] transmission_payload_echo;
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
// COMMAND - FIR Filter - 3 tap
//
wire [7:0] transmit_cmd_fir_3tap;
wire read_next_fifo_pulse_fir_3tap;
wire [7:0] transmission_payload_fir_3tap;

command_fir_filter_3tap command_fir_filter_3tap(
.clk                    (clk                ),
.reset                  (reset              ),
.is_first_packet_in_array(is_first_packet_in_array),
.fir_filter_3tap_start  (fir_filter_3tap_start),
.awaiting_payload_fir_3tap(awaiting_payload_fir_3tap   ),
.data_from_fifo         (data_out_fifo      ),

.transmit_cmd           (transmit_cmd_fir_3tap       ),
.read_next_fifo_pulse   (read_next_fifo_pulse_fir_3tap),
.data_out               (transmission_payload_fir_3tap)
);



endmodule

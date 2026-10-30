module modular_dsp(

    input               clk     , // Top level system clock input.
    input   wire        BTN1    ,
    input   wire        uart_rxd, // UART Recieve pin.
    output  wire        uart_txd // UART transmit pin.

);

// Clock frequency in hertz.
parameter CLK_HZ = 12000000;
parameter BIT_RATE =   115200;
parameter PAYLOAD_BITS = 8;

// The iCEBreaker user button is active-low; normalize it to an active-high
// reset for the synchronous modules and active-low reset for the UART blocks.
wire reset = ~BTN1;
wire resetn = BTN1;

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
buffer fifo(
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
packet_receiver #(.MAX_PAYLOAD(256)) packet_receiver(
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
.uart_tx_data           (uart_tx_data       )
);


//
// Command Handler
//
wire echo_start;
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
.echo_start             (echo_start     )
);

//
// COMMAND - Echo
//
wire [7:0] transmission_payload;
//
command_echo command_echo(
.clk                    (clk                ),
.reset                  (reset              ),
.echo_start             (echo_start         ),
.awaiting_payload       (awaiting_payload   ),
.data_from_fifo         (data_out_fifo      ),

.transmit_cmd           (transmit_cmd       ),
.read_next_fifo_pulse   (read_next_fifo_pulse),
.data_out               (transmission_payload)
);


endmodule

// Coordinates coefficient loading, stream packets, the FIR and streamed TX.
// The legacy command path owns the UART until START_STREAM is accepted.
module audio_stream_controller #(
    parameter MAX_BLOCK_BYTES = 2048,
    parameter INPUT_FIFO_BYTES = 2048,
    parameter OUTPUT_FIFO_SAMPLES = 1024,
    parameter FIR_TAPS = 64
)(
    input wire clk,
    input wire reset,

    input wire load_coefficients_start,
    input wire start_stream_request,
    input wire [15:0] legacy_payload_length,
    input wire [7:0] legacy_fifo_data,
    output wire legacy_fifo_read_enable,

    input wire uart_rx_valid,
    input wire [7:0] uart_rx_data,
    output reg stream_active,

    input wire awaiting_payload,
    input wire packet_tx_done,
    output reg [7:0] transmit_cmd,
    output reg [15:0] transmit_payload_length,
    output wire [7:0] transmission_payload,
    output reg stream_session_done
);

localparam CMD_STREAM_READY = 8'hF0;
localparam CMD_STREAM_DONE  = 8'hF1;
localparam CMD_STREAM_ERROR = 8'hF2;
localparam CMD_DATA         = 8'hFF;
localparam CMD_COEFFICIENTS = 8'h04;
localparam CMD_START_STREAM = 8'h10;

localparam SETUP_IDLE       = 3'd0;
localparam SETUP_COEFF_LOW  = 3'd1;
localparam SETUP_COEFF_HIGH = 3'd2;
localparam SETUP_START_LOW  = 3'd3;
localparam SETUP_START_HIGH = 3'd4;

localparam COPY_IDLE  = 2'd0;
localparam COPY_READ  = 2'd1;
localparam COPY_FLUSH = 2'd2;

localparam TX_IDLE       = 3'd0;
localparam TX_WAIT_READY = 3'd1;
localparam TX_WAIT_DATA  = 3'd2;
localparam TX_WAIT_FINAL = 3'd3;
localparam TX_WAIT_END   = 3'd4;

reg [2:0] setup_state;
reg [15:0] coefficient_packet_length;
reg [15:0] start_packet_length;
reg coefficient_packet_pending;
reg start_packet_pending;
reg coefficients_loaded;
reg [6:0] coefficient_index;
reg [7:0] config_low_byte;
reg [15:0] stream_block_bytes;
reg clear_stream_buffers;
reg coefficient_write_enable;
reg [5:0] coefficient_write_index;
reg signed [15:0] coefficient_write_data;
reg stream_ready_request;

reg [1:0] copy_state;
reg [15:0] copy_length;
reg [15:0] copy_index;
wire [$clog2(MAX_BLOCK_BYTES)-1:0] packet_memory_address;
wire [7:0] packet_memory_data;
wire packet_memory_data_valid;
wire packet_payload_available;
wire [15:0] packet_payload_length;
wire packet_stop_received;
wire packet_error;
reg stream_error_latched;
reg stop_pending;
reg close_stream_input_request;

wire packet_read_enable = (copy_state == COPY_READ);
wire packet_consumed = (copy_state == COPY_FLUSH);
wire packet_copy_active = (copy_state == COPY_READ) ||
                          (copy_state == COPY_FLUSH);
assign packet_memory_address = copy_index[$clog2(MAX_BLOCK_BYTES)-1:0];

stream_packet_receiver #(.MAX_PAYLOAD(MAX_BLOCK_BYTES)) stream_rx(
    .clk                    (clk),
    .reset                  (reset || clear_stream_buffers),
    .enable                 (stream_active),
    .byte_received          (uart_rx_valid),
    .data_in                (uart_rx_data),
    .payload_copy_active    (packet_copy_active),
    .payload_available      (packet_payload_available),
    .payload_length         (packet_payload_length),
    .payload_consumed       (packet_consumed),
    .payload_read_address   (packet_memory_address),
    .payload_read_enable    (packet_read_enable),
    .payload_read_data      (packet_memory_data),
    .payload_read_valid     (packet_memory_data_valid),
    .stop_received          (packet_stop_received),
    .packet_error           (packet_error)
);

wire input_fifo_empty;
wire input_fifo_full;
wire [7:0] input_fifo_data;
wire input_fifo_write_enable = packet_memory_data_valid;
wire [7:0] input_fifo_write_data = packet_memory_data;
wire [$clog2(INPUT_FIFO_BYTES+1)-1:0] input_fifo_count;
wire input_fifo_read_enable;
wire [15:0] requested_block_bytes = {legacy_fifo_data, config_low_byte};

buffer #(.DEPTH(INPUT_FIFO_BYTES), .DATA_WIDTH(8)) stream_input_fifo(
    .clk            (clk),
    .write_enable   (input_fifo_write_enable),
    .data_in        (input_fifo_write_data),
    .read_enable    (input_fifo_read_enable),
    .reset          (reset || clear_stream_buffers),
    .data_out       (input_fifo_data),
    .empty          (input_fifo_empty),
    .full           (input_fifo_full),
    .count          (input_fifo_count)
);

wire output_fifo_full;
wire output_fifo_empty;
wire [15:0] output_fifo_data;
wire [10:0] output_fifo_count;
wire output_fifo_read_enable;
wire [15:0] fir_output_sample;
wire fir_output_valid;
wire fir_busy;
wire coefficient_write_pulse = coefficient_write_enable;

buffer #(
    .DEPTH(OUTPUT_FIFO_SAMPLES),
    .DATA_WIDTH(16)
) stream_output_fifo(
    .clk            (clk),
    .write_enable   (fir_output_valid && !output_fifo_full),
    .data_in        (fir_output_sample),
    .read_enable    (output_fifo_read_enable),
    .reset          (reset || clear_stream_buffers),
    .data_out       (output_fifo_data),
    .empty          (output_fifo_empty),
    .full           (output_fifo_full),
    .count          (output_fifo_count)
);

fir_filter_core #(.TAPS(FIR_TAPS)) stream_fir(
    .clk                        (clk),
    .reset                      (reset),
    .clear_history              (clear_stream_buffers),
    .coefficient_write_enable   (coefficient_write_pulse),
    .coefficient_write_index    (coefficient_write_index),
    .coefficient_write_data     (coefficient_write_data),
    .input_empty                (input_fifo_empty),
    .input_byte                 (input_fifo_data),
    .input_read_enable          (input_fifo_read_enable),
    .output_full                (output_fifo_full),
    .output_sample              (fir_output_sample),
    .output_valid               (fir_output_valid),
    .busy                       (fir_busy)
);

// The staged payload is copied into the audio FIFO at one byte per clock.
// A packet is copied only after stream_packet_receiver verified its checksum.
wire [$clog2(INPUT_FIFO_BYTES+1)-1:0] input_fifo_space =
    INPUT_FIFO_BYTES - input_fifo_count;
assign output_fifo_read_enable = awaiting_payload && output_packet_is_data &&
                                 output_high_byte;
assign transmission_payload = output_packet_is_data ?
    (output_high_byte ? output_fifo_data[15:8] : output_fifo_data[7:0]) : 8'd0;

reg [2:0] tx_state;
reg output_packet_is_data;
reg output_high_byte;
reg tx_ready_pending;
wire output_block_ready = output_fifo_count >= (stream_block_bytes >> 1);
wire stream_work_drained = (copy_state == COPY_IDLE) &&
                           !packet_payload_available && input_fifo_empty &&
                           !fir_busy;

// Coefficient and START_STREAM payloads arrive through the legacy FIFO before
// stream mode begins. Audio packets use their own checksum-validated staging RAM.
assign legacy_fifo_read_enable =
    (setup_state == SETUP_COEFF_LOW) ||
    (setup_state == SETUP_COEFF_HIGH) ||
    (setup_state == SETUP_START_LOW) ||
    (setup_state == SETUP_START_HIGH);

always @(posedge clk) begin
    if (reset) begin
        setup_state <= SETUP_IDLE;
        coefficient_packet_length <= 16'd0;
        start_packet_length <= 16'd0;
        coefficient_packet_pending <= 1'b0;
        start_packet_pending <= 1'b0;
        coefficients_loaded <= 1'b0;
        coefficient_index <= 7'd0;
        config_low_byte <= 8'd0;
        stream_block_bytes <= 16'd0;
        clear_stream_buffers <= 1'b0;
        coefficient_write_enable <= 1'b0;
        coefficient_write_index <= 6'd0;
        coefficient_write_data <= 16'sd0;
        stream_ready_request <= 1'b0;
        stream_active <= 1'b0;
        stream_error_latched <= 1'b0;
        stop_pending <= 1'b0;
    end else begin
        clear_stream_buffers <= 1'b0;
        coefficient_write_enable <= 1'b0;
        stream_ready_request <= 1'b0;

        if (load_coefficients_start && !stream_active) begin
            coefficient_packet_pending <= 1'b1;
            coefficient_packet_length <= legacy_payload_length;
            coefficients_loaded <= 1'b0;
        end
        if (start_stream_request && !stream_active) begin
            start_packet_pending <= 1'b1;
            start_packet_length <= legacy_payload_length;
        end

        if (packet_stop_received)
            stop_pending <= 1'b1;
        if (packet_error) begin
            stream_error_latched <= 1'b1;
            stop_pending <= 1'b1;
        end

        if (stream_session_done) begin
            stream_active <= 1'b0;
            stop_pending <= 1'b0;
            stream_error_latched <= 1'b0;
        end
        if (close_stream_input_request)
            stream_active <= 1'b0;

        case (setup_state)
            SETUP_IDLE: begin
                if (coefficient_packet_pending) begin
                    coefficient_packet_pending <= 1'b0;
                    if (coefficient_packet_length == 16'd128) begin
                        coefficient_index <= 7'd0;
                        setup_state <= SETUP_COEFF_LOW;
                    end
                end else if (start_packet_pending) begin
                    start_packet_pending <= 1'b0;
                    if (start_packet_length == 16'd2)
                        setup_state <= SETUP_START_LOW;
                end
            end

            SETUP_COEFF_LOW: begin
                config_low_byte <= legacy_fifo_data;
                setup_state <= SETUP_COEFF_HIGH;
            end

            SETUP_COEFF_HIGH: begin
                coefficient_write_index <= coefficient_index[5:0];
                coefficient_write_data <= {legacy_fifo_data, config_low_byte};
                coefficient_write_enable <= 1'b1;
                if (coefficient_index == 7'd63) begin
                    coefficients_loaded <= 1'b1;
                    setup_state <= SETUP_IDLE;
                end else begin
                    coefficient_index <= coefficient_index + 1'b1;
                    setup_state <= SETUP_COEFF_LOW;
                end
            end

            SETUP_START_LOW: begin
                config_low_byte <= legacy_fifo_data;
                setup_state <= SETUP_START_HIGH;
            end

            SETUP_START_HIGH: begin
                stream_block_bytes <= {legacy_fifo_data, config_low_byte};
                if (coefficients_loaded &&
                    (requested_block_bytes >= 16'd2) &&
                    (requested_block_bytes <= MAX_BLOCK_BYTES) &&
                    !requested_block_bytes[0]) begin
                    stream_active <= 1'b1;
                    clear_stream_buffers <= 1'b1;
                    stream_ready_request <= 1'b1;
                    stop_pending <= 1'b0;
                    stream_error_latched <= 1'b0;
                end
                setup_state <= SETUP_IDLE;
            end

            default: setup_state <= SETUP_IDLE;
        endcase
    end
end

// Move one validated audio packet into the stream input FIFO.
always @(posedge clk) begin
    if (reset || clear_stream_buffers) begin
        copy_state <= COPY_IDLE;
        copy_length <= 16'd0;
        copy_index <= 16'd0;
    end else begin
        case (copy_state)
            COPY_IDLE: begin
                if (packet_payload_available &&
                    (input_fifo_space >= packet_payload_length)) begin
                    copy_length <= packet_payload_length;
                    copy_index <= 16'd0;
                    copy_state <= COPY_READ;
                end
            end

            COPY_READ: begin
                if (copy_index == copy_length - 1'b1)
                    copy_state <= COPY_FLUSH;
                else
                    copy_index <= copy_index + 1'b1;
            end

            COPY_FLUSH: copy_state <= COPY_IDLE;
            default: copy_state <= COPY_IDLE;
        endcase
    end
end

// Output packetizer. Full blocks are sent as soon as available; after STOP,
// the remaining even-length partial block is sent before the DONE packet.
always @(posedge clk) begin
    if (reset) begin
        tx_state <= TX_IDLE;
        transmit_cmd <= 8'd0;
        transmit_payload_length <= 16'd0;
        output_packet_is_data <= 1'b0;
        output_high_byte <= 1'b0;
        tx_ready_pending <= 1'b0;
        stream_session_done <= 1'b0;
        close_stream_input_request <= 1'b0;
    end else begin
        transmit_cmd <= 8'd0;
        stream_session_done <= 1'b0;
        close_stream_input_request <= 1'b0;

        if (stream_ready_request)
            tx_ready_pending <= 1'b1;

        if (awaiting_payload && output_packet_is_data) begin
            if (output_high_byte)
                output_high_byte <= 1'b0;
            else
                output_high_byte <= 1'b1;
        end

        case (tx_state)
            TX_IDLE: begin
                if (tx_ready_pending) begin
                    transmit_cmd <= CMD_STREAM_READY;
                    transmit_payload_length <= 16'd0;
                    output_packet_is_data <= 1'b0;
                    tx_ready_pending <= 1'b0;
                    tx_state <= TX_WAIT_READY;
                end else if (stream_active && output_block_ready) begin
                    transmit_cmd <= CMD_DATA;
                    transmit_payload_length <= stream_block_bytes;
                    output_packet_is_data <= 1'b1;
                    output_high_byte <= 1'b0;
                    tx_state <= TX_WAIT_DATA;
                end else if (stream_active && stop_pending && stream_work_drained) begin
                    if (output_fifo_count != 0) begin
                        transmit_cmd <= CMD_DATA;
                        transmit_payload_length <= {output_fifo_count, 1'b0};
                        output_packet_is_data <= 1'b1;
                        output_high_byte <= 1'b0;
                        tx_state <= TX_WAIT_FINAL;
                    end else begin
                        transmit_cmd <= stream_error_latched ? CMD_STREAM_ERROR :
                                                               CMD_STREAM_DONE;
                        transmit_payload_length <= 16'd0;
                        output_packet_is_data <= 1'b0;
                        close_stream_input_request <= 1'b1;
                        tx_state <= TX_WAIT_END;
                    end
                end
            end

            TX_WAIT_READY: begin
                if (packet_tx_done)
                    tx_state <= TX_IDLE;
            end

            TX_WAIT_DATA: begin
                if (packet_tx_done)
                    tx_state <= TX_IDLE;
            end

            TX_WAIT_FINAL: begin
                if (packet_tx_done)
                    tx_state <= TX_IDLE;
            end

            TX_WAIT_END: begin
                if (packet_tx_done) begin
                    stream_session_done <= 1'b1;
                    tx_state <= TX_IDLE;
                end
            end

            default: tx_state <= TX_IDLE;
        endcase
    end
end

endmodule

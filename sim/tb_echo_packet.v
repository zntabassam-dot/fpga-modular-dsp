`timescale 1ns/1ps

module tb_echo_packet;
    localparam BIT_CYCLES = 104;

    reg clk = 1'b0;
    reg BTN1 = 1'b0;
    reg uart_rxd = 1'b1;
    wire uart_txd;
    wire monitor_valid;
    wire monitor_break;
    wire [7:0] monitor_data;

    reg [7:0] response_bytes [0:31];
    reg [7:0] payload [0:4];
    integer response_count = 0;
    integer i;
    reg [7:0] checksum;

    modular_dsp dut (.clk(clk), .BTN1(BTN1), .uart_rxd(uart_rxd), .uart_txd(uart_txd));

    uart_rx #(.BIT_RATE(115200), .CLK_HZ(12000000), .PAYLOAD_BITS(8)) monitor_rx (
        .clk(clk), .resetn(BTN1), .uart_rxd(uart_txd), .uart_rx_en(1'b1),
        .uart_rx_break(monitor_break), .uart_rx_valid(monitor_valid),
        .uart_rx_data(monitor_data)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("waves/tb_echo_packet.vcd");
        $dumpvars(0, tb_echo_packet);
    end

    always @(posedge clk) begin
        if (monitor_valid) begin
            response_bytes[response_count] = monitor_data;
            response_count = response_count + 1;
        end
    end

    task send_uart_byte(input [7:0] value);
        integer bit_index;
        begin
            @(negedge clk);
            uart_rxd = 1'b0;
            repeat (BIT_CYCLES) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                @(negedge clk);
                uart_rxd = value[bit_index];
                repeat (BIT_CYCLES) @(posedge clk);
            end
            @(negedge clk);
            uart_rxd = 1'b1;
            repeat (BIT_CYCLES) @(posedge clk);
        end
    endtask

    task wait_for_response_bytes(input integer target_count);
        integer timeout_cycles;
        begin
            timeout_cycles = 0;
            while ((response_count < target_count) && (timeout_cycles < 150000)) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
            end
            #1;
            if (response_count < target_count)
                $fatal(1, "Timed out waiting for %0d response bytes; received %0d; RX=%02x valid=%b parser=%0d cmd=%02x len=%0d fifo_count=%0d echo=%b tx=%0d",
                       target_count, response_count, dut.uart_rx_data, dut.uart_rx_valid,
                       dut.packet_receiver.fsm_state, dut.receive_cmd, dut.payload_length,
                       dut.fifo.count, dut.echo_start, dut.packet_transmitter.fsm_state);
        end
    endtask

    task check_response(input integer start_index, input [15:0] length);
        integer j;
        reg [7:0] expected_checksum;
        begin
            if (response_bytes[start_index] !== 8'hA5 ||
                response_bytes[start_index + 1] !== 8'h5A ||
                response_bytes[start_index + 2] !== 8'hFF ||
                response_bytes[start_index + 3] !== length[7:0] ||
                response_bytes[start_index + 4] !== length[15:8])
                $fatal(1, "Response mismatch at %0d: %02x %02x %02x %02x %02x; expected A5 5A FF %02x %02x",
                       start_index, response_bytes[start_index], response_bytes[start_index + 1],
                       response_bytes[start_index + 2], response_bytes[start_index + 3],
                       response_bytes[start_index + 4], length[7:0], length[15:8]);

            expected_checksum = 8'hFF ^ length[7:0] ^ length[15:8];
            for (j = 0; j < length; j = j + 1) begin
                if (response_bytes[start_index + 5 + j] !== payload[j])
                    $fatal(1, "Payload byte %0d mismatch: expected %02x, got %02x",
                           j, payload[j], response_bytes[start_index + 5 + j]);
                expected_checksum = expected_checksum ^ payload[j];
            end
            if (response_bytes[start_index + 5 + length] !== expected_checksum)
                $fatal(1, "Response checksum mismatch");
        end
    endtask

    task send_echo_request(input [15:0] length, input reg corrupt_checksum);
        integer j;
        reg [7:0] request_checksum;
        begin
            request_checksum = 8'h01 ^ length[7:0] ^ length[15:8];
            for (j = 0; j < length; j = j + 1)
                request_checksum = request_checksum ^ payload[j];
            if (corrupt_checksum)
                request_checksum = request_checksum ^ 8'h01;

            send_uart_byte(8'hA5);
            send_uart_byte(8'h5A);
            send_uart_byte(8'h01);
            send_uart_byte(length[7:0]);
            send_uart_byte(length[15:8]);
            for (j = 0; j < length; j = j + 1)
                send_uart_byte(payload[j]);
            send_uart_byte(request_checksum);
        end
    endtask

    initial begin
        payload[0] = 8'h00;
        payload[1] = 8'hA5;
        payload[2] = 8'h5A;
        payload[3] = 8'hFF;
        payload[4] = 8'h7F;

        repeat (4) @(posedge clk);
        @(negedge clk);
        BTN1 = 1'b1;

        send_echo_request(16'd5, 1'b0);
        wait_for_response_bytes(11);
        check_response(0, 16'd5);

        // A bad request must produce no response and must not poison the next echo.
        payload[0] = 8'hDE;
        payload[1] = 8'hAD;
        send_echo_request(16'd2, 1'b1);
        repeat (12000) @(posedge clk);
        if (response_count != 11)
            $fatal(1, "Invalid-checksum packet produced a response");

        payload[0] = 8'h34;
        send_echo_request(16'd1, 1'b0);
        wait_for_response_bytes(18);
        check_response(11, 16'd1);

        send_echo_request(16'd0, 1'b0);
        wait_for_response_bytes(24);
        check_response(18, 16'd0);

        $display("PASS tb_echo_packet");
        $finish;
    end
endmodule

`timescale 1ns/1ps

module tb_audio_stream;
    localparam BIT_CYCLES = 8;

    reg clk = 1'b0;
    reg BTN1 = 1'b0;
    reg uart_rxd = 1'b1;
    reg monitor_resetn = 1'b0;
    wire uart_txd;
    wire monitor_valid;
    wire monitor_break;
    wire [7:0] monitor_data;

    reg [7:0] request_payload [0:511];
    reg [7:0] response_bytes [0:1023];
    integer response_count = 0;
    integer i;
    integer j;
    reg [7:0] checksum;

    modular_dsp #(.POWERUP_RESET_CYCLES(8)) dut(
        .clk(clk), .BTN1(BTN1), .uart_rxd(uart_rxd), .uart_txd(uart_txd)
    );

    uart_rx #(.BIT_RATE(1500000), .CLK_HZ(12000000), .PAYLOAD_BITS(8)) monitor_rx(
        .clk(clk), .resetn(monitor_resetn), .uart_rxd(uart_txd), .uart_rx_en(1'b1),
        .uart_rx_break(monitor_break), .uart_rx_valid(monitor_valid),
        .uart_rx_data(monitor_data)
    );

    always #5 clk = ~clk;

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

    task send_packet(input [7:0] command, input [15:0] length);
        integer j;
        begin
            checksum = command ^ length[7:0] ^ length[15:8];
            for (j = 0; j < length; j = j + 1)
                checksum = checksum ^ request_payload[j];

            send_uart_byte(8'hA5);
            send_uart_byte(8'h5A);
            send_uart_byte(command);
            send_uart_byte(length[7:0]);
            send_uart_byte(length[15:8]);
            for (j = 0; j < length; j = j + 1)
                send_uart_byte(request_payload[j]);
            send_uart_byte(checksum);
        end
    endtask

    task wait_for_response_bytes(input integer target_count);
        integer timeout_cycles;
        begin
            timeout_cycles = 0;
            while ((response_count < target_count) && (timeout_cycles < 250000)) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
            end
            #1;
            if (response_count < target_count)
                $fatal(1, "Timed out waiting for %0d response bytes; got %0d; stream_active=%b setup=%0d tx=%0d count=%0d",
                       target_count, response_count, dut.stream_active,
                       dut.audio_stream_controller.setup_state,
                       dut.packet_transmitter.fsm_state,
                       dut.audio_stream_controller.output_fifo_count);
        end
    endtask

    task check_empty_response(input integer start_index, input [7:0] command);
        begin
            if (response_bytes[start_index] !== 8'hA5 ||
                response_bytes[start_index+1] !== 8'h5A ||
                response_bytes[start_index+2] !== command ||
                response_bytes[start_index+3] !== 8'h00 ||
                response_bytes[start_index+4] !== 8'h00 ||
                response_bytes[start_index+5] !== command)
                $fatal(1, "Bad empty response packet for command %02x", command);
        end
    endtask

    initial begin
        $dumpfile("waves/tb_audio_stream.vcd");
        $dumpvars(0, tb_audio_stream);

        for (i = 0; i < 512; i = i + 1)
            request_payload[i] = 8'd0;
        request_payload[0] = 8'h00;
        request_payload[1] = 8'h40; // Tap 0 = 0.5 in signed Q1.15.

        repeat (12) @(posedge clk);
        @(negedge clk);
        monitor_resetn = 1'b1;

        send_packet(8'h04, 16'd128); // Load the 64 coefficients.
        request_payload[0] = 8'hE0;
        request_payload[1] = 8'h01; // 480-byte / 240-sample output blocks.
        send_packet(8'h10, 16'd2);   // START_STREAM(block bytes = 480).
        wait_for_response_bytes(6);
        check_empty_response(0, 8'hF0); // STREAM_READY.

        request_payload[0] = 8'hE8;
        request_payload[1] = 8'h03; // +1000
        request_payload[2] = 8'h30;
        request_payload[3] = 8'hF8; // -2000
        send_packet(8'h11, 16'd480); // Full block; next packet arrives during its copy.
        request_payload[0] = 8'hD0;
        request_payload[1] = 8'h07; // +2000
        for (i = 2; i < 480; i = i + 1)
            request_payload[i] = 8'd0;
        send_packet(8'h11, 16'd480); // A second consecutive full block.
        request_payload[0] = 8'h20;
        request_payload[1] = 8'h03; // +800; filter output is +400.
        send_packet(8'h11, 16'd2); // Final partial block.
        send_packet(8'h12, 16'd0); // STOP_STREAM.

        wait_for_response_bytes(992);
        if (response_bytes[6] !== 8'hA5 || response_bytes[7] !== 8'h5A ||
            response_bytes[8] !== 8'hFF || response_bytes[9] !== 8'hE0 ||
            response_bytes[10] !== 8'h01 || response_bytes[11] !== 8'hF4 ||
            response_bytes[12] !== 8'h01 || response_bytes[13] !== 8'h18 ||
            response_bytes[14] !== 8'hFC)
            $fatal(1, "Filtered data packet header/payload mismatch");
        checksum = 8'hFF ^ 8'hE0 ^ 8'h01;
        for (j = 0; j < 480; j = j + 1)
            checksum = checksum ^ response_bytes[11+j];
        if (response_bytes[491] !== checksum)
            $fatal(1, "Filtered data packet checksum mismatch");
        if (response_bytes[492] !== 8'hA5 || response_bytes[493] !== 8'h5A ||
            response_bytes[494] !== 8'hFF || response_bytes[495] !== 8'hE0 ||
            response_bytes[496] !== 8'h01 || response_bytes[497] !== 8'hE8 ||
            response_bytes[498] !== 8'h03)
            $fatal(1, "Second consecutive filtered data packet mismatch");
        checksum = 8'hFF ^ 8'hE0 ^ 8'h01;
        for (j = 0; j < 480; j = j + 1)
            checksum = checksum ^ response_bytes[497+j];
        if (response_bytes[977] !== checksum)
            $fatal(1, "Second filtered data packet checksum mismatch");
        if (response_bytes[978] !== 8'hA5 || response_bytes[979] !== 8'h5A ||
            response_bytes[980] !== 8'hFF || response_bytes[981] !== 8'h02 ||
            response_bytes[982] !== 8'h00 || response_bytes[983] !== 8'h90 ||
            response_bytes[984] !== 8'h01 || response_bytes[985] !== 8'h6C)
            $fatal(1, "Final partial filtered data packet mismatch");
        check_empty_response(986, 8'hF1); // STREAM_DONE.

        $display("PASS tb_audio_stream (64 coefficients, two 5 ms blocks, filter, stop/drain)");
        $finish;
    end
endmodule

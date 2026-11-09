`timescale 1ns/1ps

module tb_uart_loopback;
    localparam BIT_CYCLES = 8;

    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg tx_en = 1'b0;
    reg [7:0] tx_data = 8'b0;
    wire serial_line;
    wire tx_busy;
    wire rx_valid;
    wire rx_break;
    wire [7:0] rx_data;
    reg [7:0] expected;
    reg received = 1'b0;
    integer cycles;

    uart_tx #(.BIT_RATE(1500000), .CLK_HZ(12000000), .PAYLOAD_BITS(8)) tx (
        .clk(clk), .resetn(resetn), .uart_txd(serial_line),
        .uart_tx_busy(tx_busy), .uart_tx_en(tx_en), .uart_tx_data(tx_data)
    );

    uart_rx #(.BIT_RATE(1500000), .CLK_HZ(12000000), .PAYLOAD_BITS(8)) rx (
        .clk(clk), .resetn(resetn), .uart_rxd(serial_line), .uart_rx_en(1'b1),
        .uart_rx_break(rx_break), .uart_rx_valid(rx_valid), .uart_rx_data(rx_data)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("waves/tb_uart_loopback.vcd");
        $dumpvars(0, tb_uart_loopback);
    end

    always @(posedge clk) begin
        if (rx_valid) begin
            if (rx_data !== expected)
                $fatal(1, "UART loopback mismatch: expected %02x, got %02x", expected, rx_data);
            received <= 1'b1;
        end
    end

    task transmit_and_check(input [7:0] value);
        begin
            expected = value;
            received = 1'b0;
            wait (!tx_busy);
            @(negedge clk);
            tx_data = value;
            tx_en = 1'b1;
            @(negedge clk);
            tx_en = 1'b0;

            // Decode the TX pin with an independent exact-8-clock UART
            // timing reference; this checks the transmitted bit period too.
            @(negedge serial_line);
            repeat (BIT_CYCLES/2) @(posedge clk);
            if (serial_line !== 1'b0)
                $fatal(1, "TX start bit was not low at its midpoint");
            for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                repeat (BIT_CYCLES) @(posedge clk);
                if (serial_line !== value[bit_index])
                    $fatal(1, "TX bit %0d mismatch: expected %b, got %b",
                           bit_index, value[bit_index], serial_line);
            end
            repeat (BIT_CYCLES) @(posedge clk);
            if (serial_line !== 1'b1)
                $fatal(1, "TX stop bit was not high at its midpoint");

            cycles = 0;
            while (!received && cycles < 2000) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (!received) $fatal(1, "Timed out waiting for UART receive byte %02x", value);
            wait (!tx_busy);
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        resetn = 1'b1;
        transmit_and_check(8'hA5);
        transmit_and_check(8'h3C);
        $display("PASS tb_uart_loopback");
        $finish;
    end
endmodule

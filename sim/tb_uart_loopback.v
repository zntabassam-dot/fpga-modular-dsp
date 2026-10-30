`timescale 1ns/1ps

module tb_uart_loopback;
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

    uart_tx #(.BIT_RATE(115200), .CLK_HZ(12000000), .PAYLOAD_BITS(8)) tx (
        .clk(clk), .resetn(resetn), .uart_txd(serial_line),
        .uart_tx_busy(tx_busy), .uart_tx_en(tx_en), .uart_tx_data(tx_data)
    );

    uart_rx #(.BIT_RATE(115200), .CLK_HZ(12000000), .PAYLOAD_BITS(8)) rx (
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

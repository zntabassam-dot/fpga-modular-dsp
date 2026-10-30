`timescale 1ns/1ps

module tb_uart_rx;
    localparam BIT_CYCLES = 104;

    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg uart_rxd = 1'b1;
    wire uart_rx_break;
    wire uart_rx_valid;
    wire [7:0] uart_rx_data;
    integer received_count = 0;
    reg [7:0] last_received;

    uart_rx #(.BIT_RATE(115200), .CLK_HZ(12000000), .PAYLOAD_BITS(8)) dut (
        .clk(clk), .resetn(resetn), .uart_rxd(uart_rxd), .uart_rx_en(1'b1),
        .uart_rx_break(uart_rx_break), .uart_rx_valid(uart_rx_valid),
        .uart_rx_data(uart_rx_data)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("waves/tb_uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);
    end

    always @(posedge clk) begin
        if (uart_rx_valid) begin
            received_count = received_count + 1;
            last_received = uart_rx_data;
        end
    end

    task send_frame(input [7:0] value, input reg stop_bit);
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
            uart_rxd = stop_bit;
            repeat (BIT_CYCLES) @(posedge clk);
            @(negedge clk);
            uart_rxd = 1'b1;
            repeat (2 * BIT_CYCLES) @(posedge clk);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;

        send_frame(8'h96, 1'b1);
        if (received_count != 1 || last_received !== 8'h96)
            $fatal(1, "Valid UART frame was not received correctly");

        send_frame(8'h55, 1'b0);
        if (received_count != 1)
            $fatal(1, "UART receiver accepted a frame with a low stop bit");

        $display("PASS tb_uart_rx");
        $finish;
    end
endmodule

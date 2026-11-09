`timescale 1ps/1ps

module tb_uart_rx;
    localparam CLK_HZ = 12000000;
    localparam BIT_RATE = 1500000;
    localparam CLOCK_PERIOD_PS = 83334;
    localparam BIT_PERIOD_PS = 666667;

    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg uart_rxd = 1'b1;
    wire uart_rx_break;
    wire uart_rx_valid;
    wire [7:0] uart_rx_data;
    integer received_count = 0;
    reg [7:0] last_received;

    uart_rx #(.BIT_RATE(BIT_RATE), .CLK_HZ(CLK_HZ), .PAYLOAD_BITS(8)) dut (
        .clk(clk), .resetn(resetn), .uart_rxd(uart_rxd), .uart_rx_en(1'b1),
        .uart_rx_break(uart_rx_break), .uart_rx_valid(uart_rx_valid),
        .uart_rx_data(uart_rx_data)
    );

    always #(CLOCK_PERIOD_PS/2) clk = ~clk;

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

    task send_frame(input [7:0] value, input integer phase_ps, input reg stop_bit);
        integer bit_index;
        begin
            uart_rxd = 1'b1;
            repeat (20) @(posedge clk);
            #1;
            #(phase_ps);
            uart_rxd = 1'b0;
            #(BIT_PERIOD_PS);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rxd = value[bit_index];
                #(BIT_PERIOD_PS);
            end
            uart_rxd = stop_bit;
            #(BIT_PERIOD_PS);
            uart_rxd = 1'b1;
            #(2 * BIT_PERIOD_PS);
        end
    endtask

    integer phase_index;
    integer count_before;

    initial begin
        repeat (4) @(posedge clk);
        #1 resetn = 1'b1;

        // Sweep eight different start-edge phases relative to the FPGA clock.
        // The host UART bit period is fixed at eight FPGA clocks (1.5 Mbaud).
        for (phase_index = 0; phase_index < 8; phase_index = phase_index + 1) begin
            count_before = received_count;
            send_frame(8'h96, phase_index * CLOCK_PERIOD_PS / 8, 1'b1);
            if (received_count != count_before + 1 || last_received !== 8'h96)
                $fatal(1, "Valid frame failed at start phase %0d", phase_index);

            count_before = received_count;
            send_frame(8'h55, phase_index * CLOCK_PERIOD_PS / 8, 1'b0);
            if (received_count != count_before)
                $fatal(1, "Receiver accepted low stop bit at start phase %0d", phase_index);
        end

        $display("PASS tb_uart_rx (1.5 Mbaud, 8 start phases)");
        $finish;
    end
endmodule

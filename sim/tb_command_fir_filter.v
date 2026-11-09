`timescale 1ns/1ps

module tb_command_fir_filter;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg is_first_packet_in_array = 1'b0;
    reg fir_filter_start = 1'b0;
    reg awaiting_payload_fir_filter = 1'b0;
    reg [15:0] payload_length = 16'd0;

    reg [7:0] fifo_bytes [0:81];
    integer fifo_index = 0;
    wire [7:0] data_from_fifo = fifo_bytes[fifo_index];
    wire [7:0] transmit_cmd;
    wire read_next_fifo_pulse;
    wire [7:0] data_out;
    reg signed [15:0] expected_samples [0:40];
    integer i;

    command_fir_filter dut (
        .clk(clk),
        .reset(reset),
        .is_first_packet_in_array(is_first_packet_in_array),
        .fir_filter_start(fir_filter_start),
        .awaiting_payload_fir_filter(awaiting_payload_fir_filter),
        .payload_length(payload_length),
        .data_from_fifo(data_from_fifo),
        .transmit_cmd(transmit_cmd),
        .read_next_fifo_pulse(read_next_fifo_pulse),
        .data_out(data_out)
    );

    always #5 clk = ~clk;

    // A small FIFO model: hold its head stable until the filter reads it.
    always @(posedge clk) begin
        if (!reset && read_next_fifo_pulse) begin
            if (fifo_index >= 82)
                $fatal(1, "FIR read past the supplied input bytes");
            fifo_index <= fifo_index + 1;
        end
    end

    task start_packet(input reg first_packet, input [15:0] length);
        begin
            @(negedge clk);
            is_first_packet_in_array = first_packet;
            payload_length = length;
            fir_filter_start = 1'b1;
            @(posedge clk);
            #1;
            if (transmit_cmd !== 8'hFF)
                $fatal(1, "FIR command did not request a DATA response");
            @(negedge clk);
            fir_filter_start = 1'b0;
        end
    endtask

    task check_output_byte(input [7:0] expected);
        reg [7:0] observed;
        begin
            // This unit test omits UART header timing, so allow the FIR MAC
            // enough clocks to produce the requested sample before reading it.
            repeat (120) @(posedge clk);
            @(negedge clk);
            awaiting_payload_fir_filter = 1'b1;
            #1 observed = data_out;
            @(posedge clk);
            @(negedge clk);
            awaiting_payload_fir_filter = 1'b0;
            if (observed !== expected)
                $fatal(1, "Expected output byte %02x, got %02x", expected, observed);
        end
    endtask

    task check_output_sample(input integer sample_index);
        begin
            check_output_byte(expected_samples[sample_index][7:0]);
            check_output_byte(expected_samples[sample_index][15:8]);
        end
    endtask

    initial begin
        // An impulse followed by zeros makes the output reveal all 41 taps.
        fifo_bytes[0] = 8'h00;
        fifo_bytes[1] = 8'h40; // +16384
        for (i = 2; i < 82; i = i + 1)
            fifo_bytes[i] = 8'd0;

        expected_samples[0] = -16'sd75;
        expected_samples[1] = -16'sd101;
        expected_samples[2] = -16'sd124;
        expected_samples[3] = -16'sd141;
        expected_samples[4] = -16'sd148;
        expected_samples[5] = -16'sd141;
        expected_samples[6] = -16'sd116;
        expected_samples[7] = -16'sd69;
        expected_samples[8] = 16'sd0;
        expected_samples[9] = 16'sd92;
        expected_samples[10] = 16'sd206;
        expected_samples[11] = 16'sd338;
        expected_samples[12] = 16'sd486;
        expected_samples[13] = 16'sd641;
        expected_samples[14] = 16'sd798;
        expected_samples[15] = 16'sd949;
        expected_samples[16] = 16'sd1085;
        expected_samples[17] = 16'sd1200;
        expected_samples[18] = 16'sd1287;
        expected_samples[19] = 16'sd1342;
        expected_samples[20] = 16'sd1358;
        expected_samples[21] = 16'sd1342;
        expected_samples[22] = 16'sd1287;
        expected_samples[23] = 16'sd1200;
        expected_samples[24] = 16'sd1085;
        expected_samples[25] = 16'sd949;
        expected_samples[26] = 16'sd798;
        expected_samples[27] = 16'sd641;
        expected_samples[28] = 16'sd486;
        expected_samples[29] = 16'sd338;
        expected_samples[30] = 16'sd206;
        expected_samples[31] = 16'sd92;
        expected_samples[32] = 16'sd0;
        expected_samples[33] = -16'sd69;
        expected_samples[34] = -16'sd116;
        expected_samples[35] = -16'sd141;
        expected_samples[36] = -16'sd148;
        expected_samples[37] = -16'sd141;
        expected_samples[38] = -16'sd124;
        expected_samples[39] = -16'sd101;
        expected_samples[40] = -16'sd75;

        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // Split the impulse response over two packets to check retained history.
        start_packet(1'b1, 16'd40);
        for (i = 0; i < 20; i = i + 1)
            check_output_sample(i);

        start_packet(1'b0, 16'd42);
        for (i = 20; i < 41; i = i + 1)
            check_output_sample(i);

        if (fifo_index != 82)
            $fatal(1, "Expected to consume 82 input bytes, consumed %0d", fifo_index);

        $display("PASS tb_command_fir_filter (41 taps and packet history)");
        $finish;
    end
endmodule

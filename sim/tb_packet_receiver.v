`timescale 1ns/1ps

module tb_packet_receiver;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg byte_received = 1'b0;
    reg [7:0] data_in = 8'b0;
    wire [7:0] cmd;
    wire [15:0] payload_length;
    wire write_to_fifo_en;
    wire end_of_packet;
    wire packet_valid;
    wire valid_cmd = (cmd == 8'h01);
    integer writes = 0;
    integer writes_before_oversized;
    reg [7:0] written [0:7];

    packet_receiver #(.MAX_PAYLOAD(2)) dut (
        .clk(clk), .reset(reset), .byte_received(byte_received), .data_in(data_in),
        .valid_cmd(valid_cmd), .cmd(cmd), .payload_length(payload_length),
        .write_to_fifo_en(write_to_fifo_en), .end_of_packet(end_of_packet),
        .packet_valid(packet_valid)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("waves/tb_packet_receiver.vcd");
        $dumpvars(0, tb_packet_receiver);
    end

    always @(posedge clk) begin
        if (write_to_fifo_en) begin
            written[writes] <= data_in;
            writes <= writes + 1;
        end
    end

    task send_byte(input [7:0] value);
        begin
            @(negedge clk);
            data_in = value;
            byte_received = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            byte_received = 1'b0;
        end
    endtask

    task send_packet(input [7:0] payload0, input [7:0] payload1, input reg corrupt_checksum);
        reg [7:0] checksum;
        begin
            checksum = 8'h01 ^ 8'h02 ^ 8'h00 ^ payload0 ^ payload1;
            if (corrupt_checksum) checksum = checksum ^ 8'h01;
            send_byte(8'hA5);
            send_byte(8'h5A);
            send_byte(8'h01);
            send_byte(8'h02);
            send_byte(8'h00);
            send_byte(payload0);
            send_byte(payload1);
            send_byte(checksum);
        end
    endtask

    task send_oversized_packet;
        reg [7:0] checksum;
        begin
            checksum = 8'h01 ^ 8'h03 ^ 8'h00 ^ 8'h10 ^ 8'h20 ^ 8'h30;
            send_byte(8'hA5);
            send_byte(8'h5A);
            send_byte(8'h01);
            send_byte(8'h03);
            send_byte(8'h00);
            send_byte(8'h10);
            send_byte(8'h20);
            send_byte(8'h30);
            send_byte(checksum);
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        send_packet(8'h12, 8'hA5, 1'b0);
        #1;
        if (!end_of_packet || !packet_valid)
            $fatal(1, "Valid packet was not accepted");
        if (cmd !== 8'h01 || payload_length !== 16'd2)
            $fatal(1, "Command or payload length mismatch");
        if (writes != 2 || written[0] !== 8'h12 || written[1] !== 8'hA5)
            $fatal(1, "Payload FIFO writes were incorrect");

        // A bad checksum must end the packet but must not mark it valid.
        send_packet(8'h34, 8'h56, 1'b1);
        #1;
        if (!end_of_packet || packet_valid)
            $fatal(1, "Bad checksum handling was incorrect");
        $display("INFO: total FIFO write pulses after one valid and one invalid packet: %0d", writes);

        writes_before_oversized = writes;
        send_oversized_packet();
        #1;
        if (!end_of_packet || packet_valid)
            $fatal(1, "Oversized packet should not be accepted");
        if (writes != writes_before_oversized)
            $fatal(1, "Oversized payload should not be written to the FIFO");

        $display("PASS tb_packet_receiver");
        $finish;
    end
endmodule

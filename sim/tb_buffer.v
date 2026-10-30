`timescale 1ns/1ps

module tb_buffer;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg write_enable = 1'b0;
    reg read_enable = 1'b0;
    reg [7:0] data_in = 8'b0;
    wire [7:0] data_out;
    wire empty;
    wire full;

    buffer #(.DEPTH(4)) dut (
        .clk(clk), .write_enable(write_enable), .data_in(data_in),
        .read_enable(read_enable), .reset(reset), .data_out(data_out),
        .empty(empty), .full(full)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("waves/tb_buffer.vcd");
        $dumpvars(0, tb_buffer);
    end

    task write_byte(input [7:0] value);
        begin
            @(negedge clk);
            data_in = value;
            write_enable = 1'b1;
            @(posedge clk);
            #1;
            write_enable = 1'b0;
        end
    endtask

    task read_byte_expect(input [7:0] value);
        begin
            if (empty || data_out !== value)
                $fatal(1, "FIFO head mismatch: expected %02x, got %02x", value, data_out);
            @(negedge clk);
            read_enable = 1'b1;
            @(posedge clk);
            #1;
            read_enable = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        #1 reset = 1'b0;
        if (!empty || full) $fatal(1, "FIFO flags incorrect after reset");

        write_byte(8'h11);
        write_byte(8'h22);
        if (empty || full) $fatal(1, "FIFO flags incorrect with two entries");

        // Simultaneous read/write should preserve the number and order of entries.
        @(negedge clk);
        read_enable = 1'b1;
        write_enable = 1'b1;
        data_in = 8'h33;
        @(posedge clk);
        #1;
        read_enable = 1'b0;
        write_enable = 1'b0;
        read_byte_expect(8'h22);
        read_byte_expect(8'h33);
        if (!empty) $fatal(1, "FIFO should be empty after draining");

        write_byte(8'hA0);
        write_byte(8'hA1);
        write_byte(8'hA2);
        write_byte(8'hA3);
        if (!full) $fatal(1, "FIFO did not assert full at capacity");

        // A full FIFO must accept a replacement write if a read occurs too.
        @(negedge clk);
        read_enable = 1'b1;
        write_enable = 1'b1;
        data_in = 8'hB0;
        @(posedge clk);
        #1;
        read_enable = 1'b0;
        write_enable = 1'b0;
        if (!full) $fatal(1, "FIFO count changed on simultaneous full read/write");

        write_byte(8'hFF); // Full FIFO must reject this write.
        read_byte_expect(8'hA1);
        read_byte_expect(8'hA2);
        read_byte_expect(8'hA3);
        read_byte_expect(8'hB0);
        if (!empty) $fatal(1, "FIFO should be empty after full-depth drain");

        $display("PASS tb_buffer");
        $finish;
    end
endmodule

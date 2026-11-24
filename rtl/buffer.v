module buffer #(
    parameter DEPTH = 1024,
    parameter DATA_WIDTH = 8
)(
    input wire clk,
    input wire write_enable,
    input wire [DATA_WIDTH-1:0] data_in,
    input wire read_enable,
    input wire reset,

    output wire [DATA_WIDTH-1:0] data_out,
    output wire empty,
    output wire full,
    output wire [$clog2(DEPTH+1)-1:0] count
);

localparam PTR_WIDTH = $clog2(DEPTH);
localparam COUNT_WIDTH = $clog2(DEPTH+1);

reg [DATA_WIDTH-1:0] buffer_mem [0:DEPTH-1];
reg [PTR_WIDTH-1:0] write_ptr = 0;
reg [PTR_WIDTH-1:0] read_ptr = 0;
reg [COUNT_WIDTH-1:0] count_reg = 0;
reg [DATA_WIDTH-1:0] ram_head;
reg [DATA_WIDTH-1:0] bypass_head = 0;
reg use_bypass = 1'b1;

assign count = count_reg;
assign empty = (count_reg == 0);
assign full = (count_reg == DEPTH);

wire do_read = !reset && read_enable && !empty;
// Permit a write on the same cycle as a read, even when currently full.
wire do_write = !reset && write_enable && (!full || do_read);
wire [PTR_WIDTH-1:0] next_read_ptr =
    (read_ptr == DEPTH-1) ? {PTR_WIDTH{1'b0}} : read_ptr + 1'b1;

assign data_out = use_bypass ? bypass_head : ram_head;

// Keep the RAM port in a simple synchronous-read form so Yosys can map the
// storage array to an iCE40 block RAM.
always @(posedge clk) begin
    if (do_write)
        buffer_mem[write_ptr] <= data_in;
    if (do_read && (count_reg > 1))
        ram_head <= buffer_mem[next_read_ptr];
end

always @(posedge clk) begin
    if (reset) begin
        write_ptr <= 0;
        read_ptr <= 0;
        count_reg <= 0;
        bypass_head <= 0;
        use_bypass <= 1'b1;
    end else begin
        if (do_write) begin
            if (write_ptr == DEPTH-1)
                write_ptr <= 0;
            else
                write_ptr <= write_ptr + 1'b1;
        end

        if (do_read) begin
            if (read_ptr == DEPTH-1)
                read_ptr <= 0;
            else
                read_ptr <= read_ptr + 1'b1;
        end

        if (do_write && !do_read)
            count_reg <= count_reg + 1'b1;
        else if (do_read && !do_write)
            count_reg <= count_reg - 1'b1;

        if (do_read) begin
            if (count_reg > 1) begin
                use_bypass <= 1'b0;
            end else if (do_write) begin
                // Replacing the only queued byte: the new byte becomes head.
                bypass_head <= data_in;
                use_bypass <= 1'b1;
            end else begin
                bypass_head <= {DATA_WIDTH{1'b0}};
                use_bypass <= 1'b1;
            end
        end else if (empty && do_write) begin
            // The memory write is synchronous; bypass its input for the new head.
            bypass_head <= data_in;
            use_bypass <= 1'b1;
        end
    end
end

endmodule

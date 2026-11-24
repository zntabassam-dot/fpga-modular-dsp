// Time-multiplexed 64-tap signed Q1.15 FIR.
// One multiply-accumulate datapath is reused for every tap of each sample.
module fir_filter_core #(
    parameter TAPS = 64
)(
    input wire clk,
    input wire reset,
    input wire clear_history,

    input wire coefficient_write_enable,
    input wire [$clog2(TAPS)-1:0] coefficient_write_index,
    input wire signed [15:0] coefficient_write_data,

    input wire input_empty,
    input wire [7:0] input_byte,
    output wire input_read_enable,

    input wire output_full,
    output reg [15:0] output_sample,
    output reg output_valid,
    output wire busy
);

localparam INDEX_WIDTH = $clog2(TAPS);
localparam HISTORY_COUNT_WIDTH = $clog2(TAPS+1);

localparam STATE_IDLE      = 3'd0;
localparam STATE_READ_LOW  = 3'd1;
localparam STATE_READ_HIGH = 3'd2;
localparam STATE_MAC       = 3'd3;
localparam STATE_HISTORY   = 3'd4;
localparam STATE_OUTPUT    = 3'd5;

reg [2:0] state;
reg [7:0] sample_low_byte;
reg signed [15:0] current_sample;
reg [INDEX_WIDTH-1:0] tap_index;
reg [INDEX_WIDTH-1:0] history_write_pointer;
reg [HISTORY_COUNT_WIDTH-1:0] history_count;
reg signed [15:0] history_read_data;
reg history_read_valid;
reg signed [15:0] coefficient_read_data;
reg signed [37:0] accumulator;

reg signed [15:0] coefficients [0:TAPS-1];
// Keep the delay line in block RAM; FF implementation costs 16*TAPS LCs.
(* ram_style = "block" *) reg signed [15:0] sample_history [0:TAPS-1];

wire [INDEX_WIDTH-1:0] history_read_address =
    history_write_pointer - tap_index;
wire signed [15:0] mac_sample = (tap_index == 0) ? current_sample :
                                  (history_read_valid ? history_read_data : 16'sd0);
wire signed [31:0] product = mac_sample * coefficient_read_data;
wire signed [37:0] product_extended = {{6{product[31]}}, product};
wire signed [37:0] accumulated_value = accumulator + product_extended;
wire signed [37:0] scaled_value = accumulated_value >>> 15;
wire signed [15:0] saturated_value =
    (scaled_value > 38'sd32767) ? 16'sd32767 :
    (scaled_value < -38'sd32768) ? -16'sd32768 :
    scaled_value[15:0];

assign input_read_enable = (state == STATE_READ_LOW) ||
                           (state == STATE_READ_HIGH);
assign busy = (state != STATE_IDLE);

// Coefficients are loaded while the stream is idle. They are intentionally
// retained when stream history is cleared at the next start command.
always @(posedge clk) begin
    if (coefficient_write_enable)
        coefficients[coefficient_write_index] <= coefficient_write_data;
end

// Give the history array a plain synchronous read port. Keep startup zero
// padding in a separate flag so it does not become part of the RAM read path.
always @(posedge clk) begin
    if ((state == STATE_HISTORY) && !reset && !clear_history)
        history_read_data <= sample_history[history_read_address];

    if ((state == STATE_HISTORY) || (state == STATE_READ_HIGH))
        coefficient_read_data <= coefficients[tap_index];

    if (!reset && !clear_history && state == STATE_MAC && tap_index == TAPS-1)
        sample_history[history_write_pointer] <= current_sample;
end

always @(posedge clk) begin
    if (reset || clear_history)
        history_read_valid <= 1'b0;
    else if (state == STATE_HISTORY)
        history_read_valid <= tap_index <= history_count;
end

always @(posedge clk) begin
    if (reset) begin
        state <= STATE_IDLE;
        sample_low_byte <= 8'd0;
        current_sample <= 16'sd0;
        tap_index <= {INDEX_WIDTH{1'b0}};
        history_write_pointer <= {INDEX_WIDTH{1'b0}};
        history_count <= {HISTORY_COUNT_WIDTH{1'b0}};
        accumulator <= 38'sd0;
        output_sample <= 16'd0;
        output_valid <= 1'b0;
    end else if (clear_history) begin
        state <= STATE_IDLE;
        tap_index <= {INDEX_WIDTH{1'b0}};
        history_write_pointer <= {INDEX_WIDTH{1'b0}};
        history_count <= {HISTORY_COUNT_WIDTH{1'b0}};
        accumulator <= 38'sd0;
        output_valid <= 1'b0;
    end else begin
        case (state)
            STATE_IDLE: begin
                if (!input_empty) begin
                    state <= STATE_READ_LOW;
                    output_valid <= 1'b0;
                end
            end

            STATE_READ_LOW: begin
                sample_low_byte <= input_byte;
                tap_index <= {INDEX_WIDTH{1'b0}};
                state <= STATE_READ_HIGH;
            end

            STATE_READ_HIGH: begin
                current_sample <= {input_byte, sample_low_byte};
                tap_index <= {INDEX_WIDTH{1'b0}};
                accumulator <= 38'sd0;
                state <= STATE_MAC;
            end

            STATE_MAC: begin
                if (tap_index == TAPS-1) begin
                    output_sample <= saturated_value;
                    output_valid <= 1'b1;
                    if (history_write_pointer == TAPS-1)
                        history_write_pointer <= {INDEX_WIDTH{1'b0}};
                    else
                        history_write_pointer <= history_write_pointer + 1'b1;
                    if (history_count < TAPS-1)
                        history_count <= history_count + 1'b1;
                    state <= STATE_OUTPUT;
                end else begin
                    accumulator <= accumulated_value;
                    tap_index <= tap_index + 1'b1;
                    state <= STATE_HISTORY;
                end
            end

            STATE_HISTORY: begin
                state <= STATE_MAC;
            end

            STATE_OUTPUT: begin
                if (!output_full) begin
                    output_valid <= 1'b0;
                    state <= STATE_IDLE;
                end
            end

            default: state <= STATE_IDLE;
        endcase
    end
end

endmodule

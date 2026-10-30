IVERILOG ?= iverilog
VVP ?= vvp
BUILD_DIR ?= /tmp/modular_dsp_sim
WAVE_DIR ?= waves

.PHONY: test wave clean

test: $(BUILD_DIR)/tb_buffer $(BUILD_DIR)/tb_packet_receiver $(BUILD_DIR)/tb_uart_rx $(BUILD_DIR)/tb_uart_loopback $(BUILD_DIR)/tb_echo_packet
	mkdir -p $(WAVE_DIR)
	$(VVP) $(BUILD_DIR)/tb_buffer
	$(VVP) $(BUILD_DIR)/tb_packet_receiver
	$(VVP) $(BUILD_DIR)/tb_uart_rx
	$(VVP) $(BUILD_DIR)/tb_uart_loopback
	$(VVP) $(BUILD_DIR)/tb_echo_packet

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/tb_buffer: tb_buffer.v ../rtl/buffer.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -s tb_buffer -o $@ ../rtl/buffer.v tb_buffer.v

$(BUILD_DIR)/tb_packet_receiver: tb_packet_receiver.v ../rtl/packet_receiver.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -s tb_packet_receiver -o $@ ../rtl/packet_receiver.v tb_packet_receiver.v

$(BUILD_DIR)/tb_uart_loopback: tb_uart_loopback.v ../rtl/uart_tx.v ../rtl/uart_rx.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -s tb_uart_loopback -o $@ ../rtl/uart_tx.v ../rtl/uart_rx.v tb_uart_loopback.v

$(BUILD_DIR)/tb_uart_rx: tb_uart_rx.v ../rtl/uart_rx.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -s tb_uart_rx -o $@ ../rtl/uart_rx.v tb_uart_rx.v

$(BUILD_DIR)/tb_echo_packet: tb_echo_packet.v ../rtl/modular_dsp.v ../rtl/uart_tx.v ../rtl/uart_rx.v ../rtl/buffer.v ../rtl/packet_receiver.v ../rtl/packet_transmitter.v ../rtl/command_handler.v ../rtl/command_echo.v | $(BUILD_DIR)
	$(IVERILOG) -g2012 -s tb_echo_packet -o $@ ../rtl/modular_dsp.v ../rtl/uart_tx.v ../rtl/uart_rx.v ../rtl/buffer.v ../rtl/packet_receiver.v ../rtl/packet_transmitter.v ../rtl/command_handler.v ../rtl/command_echo.v tb_echo_packet.v

wave: test
	gtkwave $(WAVE_DIR)/tb_echo_packet.vcd

clean:
	rm -rf $(BUILD_DIR)

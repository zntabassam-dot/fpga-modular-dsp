PROJ = modular_dsp
PCF  = icebreaker.pcf
SOURCES = rtl/modular_dsp.v rtl/uart_tx.v rtl/uart_rx.v rtl/buffer.v rtl/packet_receiver.v rtl/packet_transmitter.v rtl/command_handler.v rtl/command_echo.v rtl/command_fir_filter.v rtl/command_data_in_mux.v rtl/command_data_out_mux.v

all: $(PROJ).bin

$(PROJ).json: $(SOURCES)
	yosys -p "read_verilog $(SOURCES); synth_ice40 -dsp -top $(PROJ) -json $@"

$(PROJ).asc: $(PROJ).json $(PCF)
	nextpnr-ice40 --up5k --package sg48 --freq 12 \
		--json $(PROJ).json --pcf $(PCF) --asc $@

$(PROJ).bin: $(PROJ).asc
	icepack $< $@

prog: $(PROJ).bin
	iceprog $<

clean:
	rm -f $(PROJ).json $(PROJ).asc $(PROJ).bin

test:
	$(MAKE) -C sim test

wave:
	$(MAKE) -C sim wave

.PHONY: all prog clean test wave

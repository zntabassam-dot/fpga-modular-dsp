# Transmitting PC -> FPGA

CMD_ECHO = 0x01
# FIR packets: send FIRST once, then CONTINUATION for later chunks in the same
# audio stream so the FPGA keeps the previous two samples between packets.
CMD_FIR_FIRST_PACKET = 0x02
CMD_FIR_CONTINUATION = 0x03
# CMD_SET_FIR = 0x04
# CMD_PROCESS_AUDIO = 0x10
# CMD_GET_STATUS = 0x11


# Receiving FPGA -> PC

CMD_DATA = 0xFF

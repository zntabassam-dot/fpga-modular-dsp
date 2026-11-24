# Transmitting PC -> FPGA

CMD_ECHO = 0x01
# FIR packets: send FIRST once, then CONTINUATION for later chunks in the same
# audio stream so the FPGA keeps the previous two samples between packets.
CMD_FIR_FIRST_PACKET = 0x02
CMD_FIR_CONTINUATION = 0x03
CMD_SET_STREAM_COEFFICIENTS = 0x04
CMD_START_AUDIO_STREAM = 0x10
CMD_AUDIO_BLOCK = 0x11
CMD_STOP_AUDIO_STREAM = 0x12


# Receiving FPGA -> PC

CMD_DATA = 0xFF
CMD_STREAM_READY = 0xF0
CMD_STREAM_DONE = 0xF1
CMD_STREAM_ERROR = 0xF2

import serial

from packet_commands import CMD_DATA, CMD_ECHO
from packet_controller import build_packet
from packet_response import read_packet


PORT = "/dev/ttyUSB1"
BAUD_RATE = 115200
TIMEOUT = 3

payload = bytes([0x00, 0x7F, 0x80, 0xFF, 0xA5, 0x5A])
ser = serial.Serial(port=PORT, baudrate=BAUD_RATE, timeout=TIMEOUT)

try:
    request = build_packet(CMD_ECHO, payload)
    ser.write(request)

    response_cmd, response_payload = read_packet(ser)
    if response_cmd != CMD_DATA:
        raise AssertionError(f"Expected DATA command 0xFF, got 0x{response_cmd:02X}")
    if response_payload != payload:
        raise AssertionError(
            f"Echo payload mismatch: sent {payload.hex()}, received {response_payload.hex()}"
        )

    print(f"Echo success: {response_payload.hex()}")
finally:
    ser.close()

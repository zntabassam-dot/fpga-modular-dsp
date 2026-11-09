from pathlib import Path
from time import perf_counter
import wave

import serial

from packet_commands import CMD_DATA, CMD_ECHO
from packet_controller import MAX_PAYLOAD, build_packet
from packet_response import read_packet


PORT = "/dev/ttyUSB1"
BAUD_RATE = 500000
TIMEOUT = 3
UART_BITS_PER_BYTE = 10  # 8 data bits, start bit and stop bit (8-N-1)
PACKET_OVERHEAD_BYTES = 6  # sync, command, 2-byte length and checksum

# Number of audio bytes in each request. Must not exceed the packet limit.
PAYLOAD_SIZE = 2048

# False sends one packet from the start of the WAV. True sends the whole file
# as consecutive packets, waiting for and checking each echo before continuing.
SEND_WHOLE_FILE = True

WAV_FILE = Path(__file__).with_name("audio_test.wav")


if not 1 <= PAYLOAD_SIZE <= MAX_PAYLOAD:
    raise ValueError(f"PAYLOAD_SIZE must be between 1 and {MAX_PAYLOAD}")

with wave.open(str(WAV_FILE), "rb") as wav_file:
    if wav_file.getcomptype() != "NONE":
        raise ValueError("audio_test.wav must contain uncompressed PCM audio")
    audio_bytes = wav_file.readframes(wav_file.getnframes())

if not audio_bytes:
    raise ValueError(f"No audio data found in {WAV_FILE}")

bytes_to_send = audio_bytes if SEND_WHOLE_FILE else audio_bytes[:PAYLOAD_SIZE]
# print(f"WAV audio data: {len(audio_bytes)} bytes")
print(
    f"Mode: {'Whole file' if SEND_WHOLE_FILE else '1 packet'} "
    f"\nPayload size: {PAYLOAD_SIZE} bytes"
)

packet_count = 0
byte_count = 0

with serial.Serial(port=PORT, baudrate=BAUD_RATE, timeout=TIMEOUT) as ser:
    start_time = perf_counter()
    while byte_count < len(bytes_to_send):
        payload = bytes_to_send[byte_count:byte_count + PAYLOAD_SIZE]
        request = build_packet(CMD_ECHO, payload)

        written = ser.write(request)
        if written != len(request):
            raise IOError(f"Wrote {written} of {len(request)} request bytes")
        ser.flush()

        response_cmd, response_payload = read_packet(ser)
        packet_count += 1

        if response_cmd != CMD_DATA:
            raise AssertionError(
                f"Packet {packet_count}: expected response command 0xFF, "
                f"got 0x{response_cmd:02X}"
            )
        if response_payload != payload:
            raise AssertionError(
                f"Packet {packet_count} echo mismatch: "
                f"sent {len(payload)} bytes, received {len(response_payload)} bytes; "
                f"sent [{payload.hex(' ').upper()}], "
                f"received [{response_payload.hex(' ').upper()}]"
            )

        byte_count += len(payload)
        print(f"Packet {packet_count}: echo verified ({len(payload)} bytes)")

elapsed_seconds = perf_counter() - start_time
measured_kb_per_second = byte_count / elapsed_seconds / 1000

# An echo transaction sends each payload and its response over the UART, plus
# packet framing in both directions. This is the ideal stop-and-wait ceiling.
wire_bytes_per_direction = byte_count + packet_count * PACKET_OVERHEAD_BYTES
ideal_round_trip_seconds = (
    2 * wire_bytes_per_direction * UART_BITS_PER_BYTE / BAUD_RATE
)
ideal_echo_kb_per_second = byte_count / ideal_round_trip_seconds / 1000
one_way_uart_kb_per_second = BAUD_RATE / UART_BITS_PER_BYTE / 1000

print(f"Success: verified {byte_count} echoed bytes in {packet_count} packet(s).")
print(f"Elapsed time: {elapsed_seconds:.3f} seconds")
print(f"Measured echo throughput: {measured_kb_per_second:.2f} kB/s")
print(f"One-way 8-N-1 UART limit: {one_way_uart_kb_per_second:.2f} kB/s")
print(f"Ideal stop-and-wait echo limit: {ideal_echo_kb_per_second:.2f} kB/s")
print(
    "Measured as a share of ideal echo limit: "
    f"{100 * measured_kb_per_second / ideal_echo_kb_per_second:.1f}%"
)

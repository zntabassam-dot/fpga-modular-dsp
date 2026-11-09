"""Send audio_test.wav through the FPGA FIR and compare the result."""

from pathlib import Path
from time import perf_counter
import wave

import matplotlib.pyplot as plt
import numpy as np
import serial

from packet_commands import (
    CMD_DATA,
    CMD_FIR_CONTINUATION,
    CMD_FIR_FIRST_PACKET,
)
from packet_controller import MAX_PAYLOAD, build_packet
from packet_response import read_packet
from fir_design import (
    CUTOFF_HZ,
    FIR_COEFFICIENTS_Q15,
    FIR_TAPS,
    COEFFICIENT_FRACTION_BITS,
    COEFFICIENT_SCALE,
    PASSBAND_CHECK_HZ,
    SAMPLE_RATE_HZ,
    STOPBAND_ATTENUATION_DB,
    STOPBAND_START_HZ,
    response_db,
)


PORT = "/dev/ttyUSB1"
BAUD_RATE = 1_500_000
TIMEOUT = 5
PAYLOAD_SIZE = 2048  # Keep even so packet boundaries stay on 16-bit samples.
UART_BITS_PER_BYTE = 10  # 8-N-1 framing: start + 8 data + stop bit
PACKET_OVERHEAD_BYTES = 6  # Sync, command, 2-byte length, checksum

WAV_FILE = Path(__file__).with_name("audio_test2.wav")
OUTPUT_WAV = Path(__file__).with_name("fpga_filtered.wav")
FFT_PNG = Path(__file__).with_name("fpga_fft_comparison.png")


def filter_reference(audio_bytes):
    """Apply the FPGA's Q1.15 FIR, including its truncation and saturation."""
    samples = np.frombuffer(audio_bytes, dtype="<i2")
    filtered = np.empty(len(samples), dtype="<i2")
    history = [0] * (FIR_TAPS - 1)

    for index, sample in enumerate(samples):
        sample = int(sample)
        accumulator = sample * FIR_COEFFICIENTS_Q15[0]
        for tap_index in range(1, FIR_TAPS):
            accumulator += history[tap_index - 1] * FIR_COEFFICIENTS_Q15[tap_index]

        value = accumulator >> COEFFICIENT_FRACTION_BITS
        filtered[index] = max(-32768, min(32767, value))
        history[1:] = history[:-1]
        history[0] = sample

    return filtered.astype("<i2", copy=False).tobytes()


if not 1 <= PAYLOAD_SIZE <= MAX_PAYLOAD or PAYLOAD_SIZE % 2:
    raise ValueError(f"PAYLOAD_SIZE must be even and between 2 and {MAX_PAYLOAD}")

with wave.open(str(WAV_FILE), "rb") as source:
    if source.getcomptype() != "NONE":
        raise ValueError("The input WAV must contain uncompressed PCM audio")
    if source.getnchannels() != 1 or source.getsampwidth() != 2:
        raise ValueError("The FIR demo expects mono, signed 16-bit PCM audio")

    sample_rate = source.getframerate()
    audio_bytes = source.readframes(source.getnframes())

if not audio_bytes or len(audio_bytes) % 2:
    raise ValueError("The WAV must contain a non-empty whole number of 16-bit samples")
if sample_rate != SAMPLE_RATE_HZ:
    raise ValueError(f"FIR coefficients were designed for {SAMPLE_RATE_HZ} Hz audio")

expected_bytes = filter_reference(audio_bytes)
returned_bytes = bytearray()
packet_count = 0

with serial.Serial(port=PORT, baudrate=BAUD_RATE, timeout=TIMEOUT) as ser:
    ser.reset_input_buffer()
    transfer_start = perf_counter()

    for offset in range(0, len(audio_bytes), PAYLOAD_SIZE):
        payload = audio_bytes[offset:offset + PAYLOAD_SIZE]
        expected_payload = expected_bytes[offset:offset + len(payload)]
        command = (CMD_FIR_FIRST_PACKET if offset == 0
                   else CMD_FIR_CONTINUATION)
        request = build_packet(command, payload)

        written = ser.write(request)
        if written != len(request):
            raise IOError(f"Wrote {written} of {len(request)} request bytes")
        ser.flush()

        response_cmd, response_payload = read_packet(ser)
        packet_count += 1
        if response_cmd != CMD_DATA:
            raise AssertionError(
                f"Packet {packet_count}: expected DATA command 0xFF, "
                f"got 0x{response_cmd:02X}"
            )
        if len(response_payload) != len(payload):
            raise AssertionError(
                f"Packet {packet_count}: expected {len(payload)} output bytes, "
                f"got {len(response_payload)}"
            )
        if response_payload != expected_payload:
            mismatch = next(
                i for i, (got, expected) in enumerate(
                    zip(response_payload, expected_payload)
                ) if got != expected
            )
            raise AssertionError(
                f"Packet {packet_count}: first mismatch at byte {mismatch}: "
                f"expected 0x{expected_payload[mismatch]:02X}, "
                f"got 0x{response_payload[mismatch]:02X}"
            )

        returned_bytes.extend(response_payload)
        print(f"Packet {packet_count}: verified {len(payload)} filtered bytes")

    transfer_seconds = perf_counter() - transfer_start

wire_bytes_per_direction = len(audio_bytes) + packet_count * PACKET_OVERHEAD_BYTES
ideal_round_trip_seconds = (
    2 * wire_bytes_per_direction * UART_BITS_PER_BYTE / BAUD_RATE
)
measured_kb_per_second = len(returned_bytes) / transfer_seconds / 1000
ideal_kb_per_second = len(returned_bytes) / ideal_round_trip_seconds / 1000
samples_per_second = len(returned_bytes) // 2 / transfer_seconds

with wave.open(str(OUTPUT_WAV), "wb") as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(sample_rate)
    output.writeframes(returned_bytes)

original_samples = np.frombuffer(audio_bytes, dtype="<i2").astype(np.float64)
filtered_samples = np.frombuffer(returned_bytes, dtype="<i2").astype(np.float64)

window = np.hanning(len(original_samples))
frequencies = np.fft.rfftfreq(len(original_samples), d=1 / sample_rate)
amplitude_scale = 2.0 / window.sum()

original_magnitude = np.abs(np.fft.rfft(original_samples * window)) * amplitude_scale
filtered_magnitude = np.abs(np.fft.rfft(filtered_samples * window)) * amplitude_scale
# DC and, for even lengths, Nyquist are not doubled in a single-sided FFT.
original_magnitude[0] *= 0.5
filtered_magnitude[0] *= 0.5
if len(original_samples) % 2 == 0:
    original_magnitude[-1] *= 0.5
    filtered_magnitude[-1] *= 0.5

floor = 1e-12
original_db = 20 * np.log10(np.maximum(original_magnitude, floor))
filtered_db = 20 * np.log10(np.maximum(filtered_magnitude, floor))

filter_frequencies, filter_response_db = response_db()
stopband_response = filter_response_db[filter_frequencies >= STOPBAND_START_HZ]
worst_stopband_db = float(stopband_response.max())
if worst_stopband_db > -STOPBAND_ATTENUATION_DB:
    raise AssertionError(
        f"Quantized FIR misses the {STOPBAND_ATTENUATION_DB:.0f} dB stopband target: "
        f"{worst_stopband_db:.2f} dB"
    )

figure, (audio_axis, response_axis) = plt.subplots(
    2, 1, figsize=(11, 8), sharex=True
)
audio_axis.plot(frequencies, original_db, label="Original audio", alpha=0.8)
audio_axis.plot(frequencies, filtered_db, label="FPGA FIR output", alpha=0.8)
audio_axis.set_title("Original and FPGA-filtered audio: FFT magnitude")
audio_axis.set_ylabel("Magnitude (dB, relative to full scale)")
audio_axis.grid(True, alpha=0.3)
audio_axis.legend()

response_axis.plot(filter_frequencies, filter_response_db, color="C2")
response_axis.axhline(-30, color="red", linestyle="--", label="30 dB stopband target")
response_axis.axvline(CUTOFF_HZ, color="gray", linestyle=":", label="2 kHz cutoff")
response_axis.axvline(STOPBAND_START_HZ, color="black", linestyle="--", label="4 kHz stopband")
response_axis.axvspan(0, PASSBAND_CHECK_HZ, color="green", alpha=0.08)
response_axis.set_title(f"{FIR_TAPS}-tap quantized FIR frequency response")
response_axis.set_xlabel("Frequency (Hz)")
response_axis.set_ylabel("Gain (dB)")
response_axis.set_xlim(0, sample_rate / 2)
response_axis.set_ylim(-80, 5)
response_axis.grid(True, alpha=0.3)
response_axis.legend(loc="lower left")
figure.tight_layout()
figure.savefig(FFT_PNG, dpi=150)

print(f"Success: verified {len(returned_bytes)} filtered bytes in {packet_count} packets")
print(f"Filter: {FIR_TAPS} taps, cutoff {CUTOFF_HZ} Hz")
print(f"Worst quantized stopband response from {STOPBAND_START_HZ} Hz: {worst_stopband_db:.2f} dB")
print(f"Serial round-trip time: {transfer_seconds:.3f} seconds")
print(f"Measured output throughput: {measured_kb_per_second:.2f} kB/s")
print(f"Measured sample rate: {samples_per_second:.0f} samples/s")
print(f"Ideal stop-and-wait UART limit: {ideal_kb_per_second:.2f} kB/s")
print(f"Measured share of ideal limit: {100 * measured_kb_per_second / ideal_kb_per_second:.1f}%")
print(f"Filtered WAV: {OUTPUT_WAV}")
print(f"FFT comparison: {FFT_PNG}")
print("Matplotlib is open; use its toolbar to zoom and pan, then close the window to finish.")
plt.show()

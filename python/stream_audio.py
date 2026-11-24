"""Capture microphone audio and stream it through the FPGA's 64-tap FIR."""

import argparse
from pathlib import Path
import queue
import threading
from time import perf_counter
import wave

import serial

from audio_capture import CHANNELS, SAMPLE_RATE_HZ, list_input_devices, make_input_stream
from fir_design import design_firwin_taps
from packet_commands import (
    CMD_AUDIO_BLOCK,
    CMD_DATA,
    CMD_SET_STREAM_COEFFICIENTS,
    CMD_START_AUDIO_STREAM,
    CMD_STOP_AUDIO_STREAM,
    CMD_STREAM_DONE,
    CMD_STREAM_ERROR,
    CMD_STREAM_READY,
)
from packet_controller import MAX_PAYLOAD, build_packet
from packet_response import read_packet


# Adjust these filter and block settings for experiments.
FIR_TAPS = 64
CUTOFF_HZ = 3500
STOPBAND_START_HZ = 4_000
STOPBAND_ATTENUATION_DB = 30.0
BLOCK_DURATION_MS = 5.0

PORT = "/dev/ttyUSB1"
BAUD_RATE = 1_500_000
SERIAL_TIMEOUT_SECONDS = 2
CAPTURE_QUEUE_BLOCKS = 128
OUTPUT_WAV = Path(__file__).with_name("fpga_stream_filtered.wav")
ORIGINAL_WAV = Path(__file__).with_name("fpga_stream_original.wav")
UART_BITS_PER_BYTE = 10  # 8-N-1 framing
PACKET_OVERHEAD_BYTES = 6


def _send_packet(serial_port, command, payload=b""):
    packet = build_packet(command, payload)
    written = serial_port.write(packet)
    if written != len(packet):
        raise IOError(f"Wrote {written} of {len(packet)} packet bytes")


def _coefficient_payload():
    coefficients = design_firwin_taps(
        num_taps=FIR_TAPS,
        cutoff_hz=CUTOFF_HZ,
        stopband_start_hz=STOPBAND_START_HZ,
        sample_rate_hz=SAMPLE_RATE_HZ,
        attenuation_db=STOPBAND_ATTENUATION_DB,
    )
    if len(coefficients) != FIR_TAPS:
        raise ValueError(f"Expected {FIR_TAPS} FIR coefficients")
    return b"".join(value.to_bytes(2, "little", signed=True) for value in coefficients)


def _write_wav(path, audio_bytes):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(CHANNELS)
        wav_file.setsampwidth(2)
        wav_file.setframerate(SAMPLE_RATE_HZ)
        wav_file.writeframes(audio_bytes)


def _record_and_stream(serial_port, device, block_bytes):
    audio_queue = queue.Queue(maxsize=CAPTURE_QUEUE_BLOCKS)
    capture_stop = threading.Event()
    capture_finished = threading.Event()
    capture_queue_overflow = threading.Event()
    device_input_overflow = threading.Event()
    writer_finished = threading.Event()
    worker_errors = []
    capture_statuses = set()
    stats = {"sent_bytes": 0, "sent_packets": 0}
    returned_audio = bytearray()

    def audio_callback(indata, frames, timing, status):
        if status:
            capture_statuses.add(str(status))
            if getattr(status, "input_overflow", False):
                device_input_overflow.set()
                capture_stop.set()
        try:
            audio_queue.put_nowait(indata.tobytes())
        except queue.Full:
            capture_queue_overflow.set()
            capture_stop.set()

    def capture_worker():
        try:
            with make_input_stream(
                audio_callback, device=device, blocksize=max(1, block_bytes // 2)
            ):
                capture_stop.wait()
        except Exception as exc:
            worker_errors.append(exc)
            capture_stop.set()
        finally:
            capture_finished.set()

    def serial_writer_worker():
        pending_audio = bytearray()
        try:
            with wave.open(str(ORIGINAL_WAV), "wb") as original_wav:
                original_wav.setnchannels(CHANNELS)
                original_wav.setsampwidth(2)
                original_wav.setframerate(SAMPLE_RATE_HZ)

                while not capture_finished.is_set() or not audio_queue.empty():
                    try:
                        audio_block = audio_queue.get(timeout=0.05)
                    except queue.Empty:
                        continue
                    original_wav.writeframesraw(audio_block)
                    pending_audio.extend(audio_block)

                    while len(pending_audio) >= block_bytes:
                        payload = bytes(pending_audio[:block_bytes])
                        del pending_audio[:block_bytes]
                        _send_packet(serial_port, CMD_AUDIO_BLOCK, payload)
                        stats["sent_bytes"] += len(payload)
                        stats["sent_packets"] += 1

                if pending_audio:
                    if len(pending_audio) % 2:
                        raise ValueError("Captured audio ended on a partial 16-bit sample")
                    _send_packet(serial_port, CMD_AUDIO_BLOCK, bytes(pending_audio))
                    stats["sent_bytes"] += len(pending_audio)
                    stats["sent_packets"] += 1

                _send_packet(serial_port, CMD_STOP_AUDIO_STREAM)
                serial_port.flush()
        except Exception as exc:
            worker_errors.append(exc)
            capture_stop.set()
        finally:
            writer_finished.set()

    def wait_for_stop_enter():
        try:
            input("Streaming. Press Enter to stop and drain the FPGA output...\n")
        except (EOFError, KeyboardInterrupt):
            pass
        capture_stop.set()

    capture_thread = threading.Thread(target=capture_worker, daemon=True)
    writer_thread = threading.Thread(target=serial_writer_worker, daemon=True)
    stop_thread = threading.Thread(target=wait_for_stop_enter, daemon=True)

    capture_thread.start()
    writer_thread.start()
    stop_thread.start()

    start_time = perf_counter()
    last_progress_time = start_time
    stream_done = False
    try:
        while not stream_done:
            try:
                response_command, response_payload = read_packet(serial_port)
            except TimeoutError:
                if worker_errors:
                    raise RuntimeError(f"Audio stream worker failed: {worker_errors[0]}")
                continue

            if response_command == CMD_DATA:
                if len(response_payload) % 2:
                    raise ValueError("FPGA returned an odd number of bytes in an audio block")
                returned_audio.extend(response_payload)
                now = perf_counter()
                if now - last_progress_time >= 1.0:
                    print(f"Received {len(returned_audio)} filtered bytes")
                    last_progress_time = now
            elif response_command == CMD_STREAM_ERROR:
                raise RuntimeError("FPGA reported a stream packet or buffer error")
            elif response_command == CMD_STREAM_DONE:
                stream_done = True
            else:
                raise ValueError(
                    f"Unexpected FPGA response command 0x{response_command:02X}"
                )
    finally:
        capture_stop.set()
        capture_thread.join(timeout=2)
        writer_thread.join(timeout=5)

    elapsed_seconds = perf_counter() - start_time

    if capture_thread.is_alive() or writer_thread.is_alive() or not writer_finished.is_set():
        raise TimeoutError("Timed out while stopping the microphone or serial writer")
    if worker_errors:
        raise RuntimeError(f"Audio stream worker failed: {worker_errors[0]}")
    if capture_statuses:
        print("Microphone status: " + "; ".join(sorted(capture_statuses)))
    if device_input_overflow.is_set():
        raise RuntimeError("PortAudio reported microphone input overflow; audio was dropped")
    if capture_queue_overflow.is_set():
        raise RuntimeError(
            f"The host audio queue filled ({CAPTURE_QUEUE_BLOCKS} blocks); "
            "the serial writer could not keep up with microphone capture"
        )

    _write_wav(OUTPUT_WAV, returned_audio)
    if len(returned_audio) != stats["sent_bytes"]:
        raise RuntimeError(
            f"Stream length mismatch: sent {stats['sent_bytes']} audio bytes, "
            f"received {len(returned_audio)} filtered bytes. Partial output saved to {OUTPUT_WAV}"
        )

    throughput_kb_s = len(returned_audio) / max(elapsed_seconds, 1e-9) / 1000
    print(f"Stream completed: {stats['sent_bytes']} input bytes in {stats['sent_packets']} packets")
    print(f"Saved original audio to {ORIGINAL_WAV}")
    print(f"Saved {len(returned_audio)} filtered bytes to {OUTPUT_WAV}")
    print(f"Elapsed after start: {elapsed_seconds:.2f} seconds; return throughput {throughput_kb_s:.2f} kB/s")


def main():
    parser = argparse.ArgumentParser(
        description="Stream headset microphone audio through the FPGA's 64-tap FIR."
    )
    parser.add_argument("--port", default=PORT, help=f"serial device (default: {PORT})")
    parser.add_argument("--device", help="microphone device index or name")
    parser.add_argument("--list-devices", action="store_true", help="list microphone inputs and exit")
    args = parser.parse_args()

    if args.list_devices:
        list_input_devices()
        return

    block_samples_exact = SAMPLE_RATE_HZ * BLOCK_DURATION_MS / 1000
    block_samples = round(block_samples_exact)
    if abs(block_samples - block_samples_exact) > 1e-9:
        raise ValueError("BLOCK_DURATION_MS must produce a whole number of audio samples")
    block_bytes = block_samples * 2
    if not 1 <= block_bytes <= MAX_PAYLOAD or block_bytes % 2:
        raise ValueError(f"Each audio block must be even and at most {MAX_PAYLOAD} bytes")

    wire_rate = (block_bytes + PACKET_OVERHEAD_BYTES) / (BLOCK_DURATION_MS / 1000)
    one_way_limit = BAUD_RATE / UART_BITS_PER_BYTE
    if wire_rate >= one_way_limit:
        raise ValueError(
            f"{BLOCK_DURATION_MS:g} ms blocks need {wire_rate / 1000:.1f} kB/s, "
            f"above the UART's {one_way_limit / 1000:.1f} kB/s one-way limit"
        )

    coefficient_bytes = _coefficient_payload()
    if len(coefficient_bytes) != FIR_TAPS * 2:
        raise AssertionError("Coefficient packet size does not match the 64-tap interface")

    print(
        f"Filter: {FIR_TAPS} taps, {CUTOFF_HZ} Hz cutoff, "
        f"{STOPBAND_START_HZ} Hz stopband start"
    )
    print(
        f"Audio blocks: {block_samples} samples / {block_bytes} bytes "
        f"({BLOCK_DURATION_MS:g} ms each)"
    )

    with serial.Serial(
        port=args.port,
        baudrate=BAUD_RATE,
        timeout=SERIAL_TIMEOUT_SECONDS,
        write_timeout=SERIAL_TIMEOUT_SECONDS,
    ) as serial_port:
        serial_port.reset_input_buffer()
        _send_packet(serial_port, CMD_SET_STREAM_COEFFICIENTS, coefficient_bytes)
        input("Coefficients sent. Press Enter to start the audio stream...")
        _send_packet(
            serial_port,
            CMD_START_AUDIO_STREAM,
            block_bytes.to_bytes(2, "little"),
        )

        response_command, response_payload = read_packet(serial_port)
        if response_command != CMD_STREAM_READY or response_payload:
            raise RuntimeError(
                f"Expected STREAM_READY (0x{CMD_STREAM_READY:02X}), got "
                f"0x{response_command:02X} with {len(response_payload)} payload bytes"
            )
        print("FPGA is ready; microphone capture is starting.")
        _record_and_stream(serial_port, args.device, block_bytes)


if __name__ == "__main__":
    main()

"""Capture mono 16-bit PCM audio from an input device and optionally save WAV."""

import argparse
from pathlib import Path
import threading
import wave


# Match the format expected by the current FPGA FIR demonstration.
SAMPLE_RATE_HZ = 48_000
CHANNELS = 1
SAMPLE_WIDTH_BYTES = 2
MAX_RECORD_SECONDS = 20
DEFAULT_OUTPUT = Path(__file__).with_name("recorded_audio.wav")


def _load_sounddevice():
    """Import sounddevice only when capture is requested."""
    try:
        import sounddevice as sd
    except ImportError as exc:
        raise SystemExit(
            "Missing dependency: install it with `python3 -m pip install sounddevice`"
        ) from exc
    except OSError as exc:
        raise SystemExit(
            "sounddevice is installed, but the PortAudio system library is missing.\n"
            "On Ubuntu/WSL, install it with `sudo apt install libportaudio2`, "
            "then try --list-devices again."
        ) from exc
    return sd


def list_input_devices(sd):
    """Print input-capable audio devices so a headset mic can be selected."""
    devices = sd.query_devices()
    default_input = sd.default.device[0]
    print("Input devices:")
    for index, device in enumerate(devices):
        if device["max_input_channels"] > 0:
            marker = " (default)" if index == default_input else ""
            print(f"  {index}: {device['name']}{marker}")


def _device_argument(value):
    """Interpret a numeric device argument as an index, otherwise as a name."""
    if value is None:
        return None
    try:
        return int(value)
    except ValueError:
        return value


def record_audio(output_path=DEFAULT_OUTPUT, max_seconds=MAX_RECORD_SECONDS,
                 save=True, device=None, on_audio_block=None):
    """Record until Enter is pressed or the time limit expires.

    If ``save`` is false, captured blocks are discarded. This keeps unlimited
    capture bounded in memory and leaves the callback ready to feed a streaming
    queue in a later version.
    """
    sd = _load_sounddevice()
    stop_requested = threading.Event()
    audio_blocks = []
    status_messages = set()

    def audio_callback(indata, frames, timing, status):
        if status:
            status_messages.add(str(status))
        if save or on_audio_block is not None:
            # Copy this block because sounddevice reuses its callback buffer.
            audio_block = indata.tobytes()
            if save:
                audio_blocks.append(audio_block)
            if on_audio_block is not None:
                # Keep this handler short and non-blocking; a later FPGA sender
                # should enqueue blocks and let a separate thread send packets.
                on_audio_block(audio_block)

    input_device = _device_argument(device)
    try:
        stream = sd.InputStream(
            samplerate=SAMPLE_RATE_HZ,
            channels=CHANNELS,
            dtype="int16",
            device=input_device,
            callback=audio_callback,
        )
    except Exception as exc:
        raise SystemExit(
            f"Could not open the audio input: {exc}\n"
            "Use --list-devices to check whether the headset microphone is visible."
        ) from exc

    input_thread = threading.Thread(
        target=lambda: _wait_for_enter(stop_requested), daemon=True
    )
    input("Press Enter to start recording...")
    print("Recording. Press Enter to stop.")
    reached_time_limit = False

    try:
        with stream:
            input_thread.start()
            if max_seconds is None:
                stop_requested.wait()
            else:
                reached_time_limit = not stop_requested.wait(timeout=max_seconds)
    except KeyboardInterrupt:
        # Ctrl+C is also a convenient way to stop an unlimited recording.
        stop_requested.set()
    except Exception as exc:
        raise SystemExit(
            f"Could not start or continue audio capture: {exc}\n"
            "Use --list-devices to check whether the headset microphone is visible."
        ) from exc

    if reached_time_limit:
        print(f"Reached the {max_seconds:g}-second recording limit.")

    total_bytes = sum(len(block) for block in audio_blocks)
    recorded_frames = total_bytes // (CHANNELS * SAMPLE_WIDTH_BYTES)
    elapsed_seconds = recorded_frames / SAMPLE_RATE_HZ

    if status_messages:
        print("Audio input reported: " + "; ".join(sorted(status_messages)))

    if not save:
        print("Stopped; audio was not saved.")
        return
    if recorded_frames == 0:
        print("No audio samples were captured; no WAV file was written.")
        return

    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(output_path), "wb") as wav_file:
        wav_file.setnchannels(CHANNELS)
        wav_file.setsampwidth(SAMPLE_WIDTH_BYTES)
        wav_file.setframerate(SAMPLE_RATE_HZ)
        wav_file.writeframes(b"".join(audio_blocks))

    print(f"Saved {recorded_frames} samples ({elapsed_seconds:.2f} seconds) to {output_path}")


def _wait_for_enter(stop_requested):
    try:
        input()
    except (EOFError, KeyboardInterrupt):
        pass
    stop_requested.set()


def main():
    parser = argparse.ArgumentParser(
        description="Record mono 48 kHz, 16-bit PCM audio from a microphone."
    )
    parser.add_argument(
        "--output", type=Path, default=DEFAULT_OUTPUT,
        help=f"output WAV path (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--device",
        help="input device index or name; omit to use the system default",
    )
    parser.add_argument(
        "--list-devices", action="store_true",
        help="list available microphone/input devices and exit",
    )
    parser.add_argument(
        "--no-save", action="store_true",
        help="capture audio but discard it instead of writing a WAV file",
    )
    parser.add_argument(
        "--unlimited", action="store_true",
        help="record until Enter/Ctrl+C; requires --no-save to avoid unbounded memory use",
    )
    args = parser.parse_args()

    sd = _load_sounddevice()
    if args.list_devices:
        list_input_devices(sd)
        return
    if args.unlimited and not args.no_save:
        parser.error("--unlimited currently requires --no-save")

    max_seconds = None if args.unlimited else MAX_RECORD_SECONDS
    record_audio(
        output_path=args.output,
        max_seconds=max_seconds,
        save=not args.no_save,
        device=args.device,
    )


if __name__ == "__main__":
    main()

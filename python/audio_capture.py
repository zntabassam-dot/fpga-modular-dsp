"""Shared microphone setup for file recording and FPGA streaming scripts."""

SAMPLE_RATE_HZ = 48_000
CHANNELS = 1


def load_sounddevice():
    try:
        import sounddevice as sd
    except ImportError as exc:
        raise SystemExit(
            "Missing dependency: install it with `python3 -m pip install sounddevice`"
        ) from exc
    except OSError as exc:
        raise SystemExit(
            "sounddevice is installed, but PortAudio is missing. On Ubuntu/WSL, "
            "install it with `sudo apt install libportaudio2`."
        ) from exc
    return sd


def resolve_input_device(value):
    """Treat numeric device arguments as indices and other values as names."""
    if value is None:
        return None
    try:
        return int(value)
    except ValueError:
        return value


def list_input_devices():
    """Print the available input devices and identify the default input."""
    sd = load_sounddevice()
    devices = sd.query_devices()
    default_input = sd.default.device[0]
    print("Input devices:")
    for index, device in enumerate(devices):
        if device["max_input_channels"] > 0:
            marker = " (default)" if index == default_input else ""
            print(f"  {index}: {device['name']}{marker}")


def make_input_stream(callback, device=None, blocksize=0):
    """Create the shared mono, signed 16-bit, 48 kHz input stream."""
    sd = load_sounddevice()
    try:
        return sd.InputStream(
            samplerate=SAMPLE_RATE_HZ,
            channels=CHANNELS,
            dtype="int16",
            device=resolve_input_device(device),
            blocksize=blocksize,
            callback=callback,
        )
    except Exception as exc:
        raise RuntimeError(
            f"Could not configure the microphone input: {exc}. "
            "Run with --list-devices and select a visible input device."
        ) from exc

import time
import wave
import struct
import serial

WAV_FILE = "audio_test.wav"

with wave.open(WAV_FILE, "rb") as wav:
    sample_rate = wav.getframerate()
    channels = wav.getnchannels()
    bits_per_sample = wav.getsampwidth() * 8
    num_frames = wav.getnframes()
    raw = wav.readframes(num_frames)

print(f"num_frames = {num_frames}")
print(f"First 8 bytes are {raw[0:7]}")

num = bytes([0x12, 0xb4, 0xa6, 0x5d, 0xf2])
print(f"Test print: {num}")         # using bytes(num) without the [] provides 17 zero bytes
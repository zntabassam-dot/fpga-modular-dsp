# Modular Design for Audio Signal Processing on an FPGA

An in-progress project exploring hardware acceleration for digital audio processing using an FPGA.

## Functionality

- PC constructs packets with a command and payload, sent via USB/UART to FPGA (Complete)
- FPGA detects packet signature, recognizes command, and buffers incoming payload (Complete)
- FPGA executes requested commands, and sends processed data back to PC (Complete)
- FPGA features an echo command, which verifies communication by returning the payload (Complete)
- FPGA supports packet-at-a-time 41-tap FIR processing (hardware validation pending)
- FPGA supports a continuous 64-tap FIR stream with coefficients loaded by the PC (simulation implemented; hardware validation pending)

## Secondary aims

- Implement a comparable system on C, and running on a synthesized RISC-V CPU (PicoRV32) (Incomplete)
- Benchmark the resource utilisation and processing time against the firmware implementation (Incomplete)

## Platform

- **Board:** iCEBreaker with an iCE40UP5K FPGA (SG48 package)
- **FPGA system clock:** 12 MHz
- **UART:** 1,500,000 baud, 8 data bits, no parity, 1 stop bit (8-N-1)
- **RTL:** Verilog
- **FPGA toolchain:** OSS CAD Suite (Yosys, nextpnr, icepack)

## Repository layout

- `rtl/` — Synthesizable Verilog files
- `sim/` — Verilog testbenches and simulation
- `python/` — PC-side packet handler and audio test input
- `Makefile` — FPGA build, clean, and program
- `icebreaker.pcf` — Board pin constraints

## Notes

The stream uses the existing `A5 5A` packet framing and checksum. Python sends 64 signed Q1.15 coefficients, then a start packet containing the audio block size. Each audio block is a normal framed packet; the FPGA returns filtered-data packets while receiving continues. The stop packet asks the FPGA to finish queued samples and send a completion packet.

### Live microphone stream

The stream client expects 48 kHz, mono, signed 16-bit PCM from the selected microphone. Adjust the cutoff, stopband start and `BLOCK_DURATION_MS` near the top of `python/stream_audio.py`. The hardware tap count is fixed at 64. The default block is 5 ms (240 samples / 480 bytes).

```bash
python3 -m pip install -r python/requirements.txt
sudo apt install libportaudio2
python3 python/stream_audio.py --list-devices
python3 python/stream_audio.py --device 3
```

The client loads coefficients, waits for Enter to start capture, and waits for another Enter to stop. It saves the captured input to `python/fpga_stream_original.wav` and the returned samples to `python/fpga_stream_filtered.wav`. Microphone capture requires `sounddevice` and the system PortAudio library on Linux.

The continuous stream path and existing echo/FIR paths pass their Icarus simulations. FPGA synthesis, resource use and live microphone-to-board operation still need to be checked on the target toolchain and hardware.

# Modular Design for Audio Signal Processing on an FPGA

An in-progress project exploring hardware acceleration for digital audio processing using an FPGA.

## Functionality

- PC constructs packets with a command and payload, sent via USB/UART to FPGA (Complete)
- FPGA detects packet signature, recognizes command, and buffers incoming payload (Complete)
- FPGA executes requested commands, and sends processed data back to PC (Complete)
- FPGA features an echo command, which verifies communication by returning the payload (Complete)
- Implement commands to filter/process uncompressed audio bytes as desired (Incomplete)

## Secondary aims

- Implement a comparable system on C, and running on a synthesized RISC-V CPU (PicoRV32) (Incomplete)
- Benchmark the resource utilisation and processing time against the firmware implementation (Incomplete)

## Platform

- **Board:** iCEBreaker with an iCE40UP5K FPGA (SG48 package)
- **FPGA system clock:** 12 MHz
- **UART:** 115200 baud, 8 data bits, no parity, 1 stop bit (8-N-1)
- **RTL:** Verilog
- **FPGA toolchain:** OSS CAD Suite (Yosys, nextpnr, icepack)

## Repository layout

- `rtl/` — Synthesizable Verilog files
- `sim/` — Verilog testbenches and simulation
- `python/` — PC-side packet handler and audio test input
- `Makefile` — FPGA build, clean, and program
- `icebreaker.pcf` — Board pin constraints

## Notes

The communication has been simulated successfully with testbenches, yet the echo command appears to not return any data on the actual hardware. This is currently being debugged.
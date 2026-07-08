# CNN Hardware Accelerator

[![Hardware: Target FPGA](https://img.shields.io/badge/Hardware-FPGA-blue)](#)
[![Language: SystemVerilog](https://img.shields.io/badge/Language-SystemVerilog-green)](#)
[![Interface: AXI4-Full](https://img.shields.io/badge/Interface-AXI4-orange)](#)

A high-performance, RTL-based Convolutional Neural Network (CNN) hardware accelerator designed for FPGA implementation. This project features a parameterized 2D systolic array architecture, custom AXI4 Direct Memory Access (DMA) controllers, and an integrated microcode layer sequencer to enable autonomous multi-layer inference with minimal host CPU intervention.

## 📌 Architecture Overview

The accelerator is built to maximize throughput and minimize off-chip memory access latencies. The core computational engine is a strictly quantized INT8 pipeline mapped to hardware DSP slices, supported by a ping-pong memory buffering scheme.

### Key Features
*   **2D Systolic Array Compute Core:** A parameterized `ROWS` x `COLS` grid of Processing Elements (PEs) designed for efficient matrix multiplication and 2D convolutions.
*   **DSP-Optimized MAC Units:** Each PE features a 3-stage pipeline (AREG, MREG, PREG) to map efficiently to Xilinx DSP48 slices, ensuring high maximum clock frequencies ($F_{max}$).
*   **Ping-Pong BRAM Buffering:** Dual-banked on-chip memory allows the AXI DMA to pre-fetch the next layer's activations and weights while the systolic array concurrently computes the current layer.
*   **Autonomous Layer Sequencer:** An integrated microcode ROM fetches and decodes instructions to update base pointers and quantization parameters dynamically, reducing host CPU overhead.
*   **Hardware Post-Processing:** Integrated logic for bias addition, ReLU activation, dynamic bit-shifting (scaling), and saturation clamping.
*   **AXI4-Full Interface:** Custom read and write DMA engines handle high-throughput burst transactions directly to and from external memory.


## ⚙️ Integration & Usage

Designed as a memory-mapped hardware accelerator that can be integrated into a RISC-V SoC through a standard AXI4 interconnect, supporting host-controlled and autonomous inference modes.

### Host CPU Control (Manual Mode)
The host processor can control the accelerator via the memory-mapped CSR interface:
1. Write the activation, weight, and output base addresses to the CSR.
2. Write the quantization bias and shift values.
3. Assert the `core_start` bit at address `0x00`.

### Autonomous Mode
Pre-load the network's memory map and quantization steps into the `microcode_rom` within `layer_sequencer.sv`. Assert the `seq_start` signal to trigger full, multi-layer inference without further host intervention.

## 🛠️ Prerequisites & Setup

*   **Simulation:** ModelSim, QuestaSim, or Vivado Simulator (XSim).
*   **Synthesis:** Xilinx Vivado (Targeting Artix-7 or similar architectures).

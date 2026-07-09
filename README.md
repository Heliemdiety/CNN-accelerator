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


## 📂 Repository Structure

The repository is organized into RTL source files (`src/`) and Design Verification testbenches (`dv/`).

### 📁 `src/` (RTL Source Files)
*   **Top-Level & Architecture**
    *   `cnn_top.sv`: Top-level module integrating the CSR, DMA engines, memory buffers, and compute core.
    *   `cnn_pkg.sv`: Global package defining strict data types and parameterized array dimensions.
*   **Compute Core**
    *   `systolic_array_2d.sv`: The scalable 2D mesh of MAC units managing the routing of activations and partial sums.
    *   `mac_pe.sv`: The foundational Multiply-Accumulate Processing Element mapped to DSP slices.
    *   `cnn_post_process.sv`: Post-computation scaling, bias addition, and ReLU activation unit.
*   **Memory & Bus Interface**
    *   `cnn_dma_read.sv` / `cnn_dma_write.sv`: FSM-driven AXI4 memory controllers for burst data transfers.
    *   `ping_pong_bram.sv`: Dual-port memory wrapper managing the latency-hiding buffer swaps.
    *   `dp_bram.sv`: True dual-port block RAM utilized for internal caching and output storage.
*   **Control Logic**
    *   `layer_sequencer.sv`: Microcode executor for autonomous multi-layer network execution.
    *   `cnn_csr.sv`: Memory-mapped Control and Status Registers for host CPU interfacing.
    *   `cnn_sys_ctrl.sv` & `address_gen.sv`: Pipeline control and memory address generation for the systolic array.

### 📁 `dv/` (Design Verification & Testbenches)
*   **System-Level Verification**
    *   `cnn_top_tb.sv`: Full system top-level testbench verifying complete inference cycles.
    *   `cnn_top_tb_8x8.sv`: Scaled system testbench verifying the parameterized 8x8 array configuration.
*   **Compute Core Unit Tests**
    *   `tb_systolic_array.sv`: Verification of the 2D mesh data routing and multi-cycle latency skew.
    *   `tb_mac_pe.sv`: Cycle-accurate DSP pipeline verification for the individual processing element.
    *   `tb_post_process.sv`: Unit test for quantization, shifting, and saturation clamping logic.
*   **Memory & DMA Unit Tests**
    *   `tb_cnn_dma_read.sv` & `tb_cnn_dma_write.sv`: Verification of AXI4 burst transactions and memory handshaking.
    *   `tb_ping_pong.sv` & `tb_dp_bram.sv`: Read/write collision and buffer-swapping verification.
*   **Control Logic Unit Tests**
    *   `tb_layer_sequencer.sv`: Verification of microcode decoding and hardware trigger sequencing.
    *   `tb_cnn_sys_ctrl.sv` & `tb_address_gen.sv`: Unit tests for pipeline draining and address boundaries.
    *   `tb_cnn_csr.sv`: CPU read/write transaction verification for the control registers.


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
*   **Current Implementation** Post-implementation Fmax: 154 MHz (Xilinx Artix-7 FPGA).

# Stage 9 UART RX Byte Interface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Pangu 200 Pro+ physical UART0 RX input and a reusable 8-N-1 byte receiver to the Stage 9 Catmull–Rom project.

**Architecture:** Constrain a new top-level `uart0_rx` port to the board's UART0_RX pin P14. Synchronize the asynchronous line into `core_clk`, decode 115200 baud 8-N-1, and expose a one-cycle byte-valid pulse, received byte, and framing-error pulse. Keep the receiver disconnected from interpolation selection and homography updates.

**Tech Stack:** SystemVerilog, Pango PDS 2022.2-SP6.4, Fabric Debugger / board USB-UART CP2102.

## Global Constraints

- Only modify `fpga/project/stage9_bicubic_catmull_rom/` and the Stage 9 chat/design/plan documentation.
- Use `uart0_rx` on board pin `P14`, `LVCMOS33`, 115200 baud, 8 data bits, no parity, one stop bit.
- Use `core_clk` with default `CLK_HZ=125000000` and hold the receiver in reset while `ddr_init_done` is low.
- Do not use L8 for UART; it is already assigned to `mem_dq[3]`.
- Do not add TX, packet framing, CRC, a FIFO, command decoding, interpolation switching, or homography updates.
- Do not alter the Catmull–Rom pixel path or Stage 8.

---

### Task 1: Implement the reusable UART byte receiver

**Files:**
- Create: `fpga/project/stage9_bicubic_catmull_rom/source/rtl/control/uart_rx_8n1.sv`

**Interface:**
- Inputs: `clk`, active-low synchronous-to-module `rstn`, asynchronous `rx`.
- Parameters: `CLK_HZ=125000000`, `BAUD_RATE=115200`.
- Outputs: `byte_data[7:0]`, one-cycle `byte_valid`, and one-cycle `frame_error`.

- [x] Create `source/rtl/control/` if it does not exist.
- [x] Add a two-flop RX synchronizer and initialize the synchronized idle state high on reset.
- [x] Implement IDLE, START, DATA, and STOP sampling with integer clocks-per-bit rounding, half-bit start validation, eight LSB-first data samples, and a center stop-bit check.
- [x] Pulse `byte_valid` only for a high stop bit; pulse `frame_error` for a low stop bit and discard that byte.
- [x] Keep receiver sampling independent of frame-processing ready/valid signals; do not add a FIFO.

### Task 2: Connect the receiver to the Stage 9 board top

**Files:**
- Modify: `fpga/project/stage9_bicubic_catmull_rom/source/rtl/HDMI_IN_DDR3_HDMI_OUT_top.v`
- Modify: `fpga/project/stage9_bicubic_catmull_rom/HDMI_IN_DDR3_HDMI_OUT_top.fdc`
- Modify: `fpga/project/stage9_bicubic_catmull_rom/HDMI_IN_DDR3_HDMI_OUT.pds`

**Connection:**
- Top-level port: `input wire uart0_rx`.
- Receiver instance clock/reset: `core_clk` / `ddr_init_done`.
- Internal outputs: `uart_rx_data[7:0]`, `uart_rx_valid`, `uart_rx_frame_error`.

- [x] Add `uart0_rx` to the top-level module and assign it to P14 as an LVCMOS33 input with pull-up.
- [x] Instantiate `uart_rx_8n1` with 125 MHz and 115200 baud parameters; connect its outputs only to internal wires.
- [x] Add the new source file to the Stage 9 PDS source list.
- [x] Preserve the existing `fram_buf` angle inputs tied low and leave all image datapath connections unchanged.

### Task 3: Document the host-side serial settings and check the integration diff

**Files:**
- Modify: `fpga/project/stage9_bicubic_catmull_rom/README.md`
- Modify: `docs/chat/新增算法.md`

- [x] Document the board's CP2102 COM port settings as 115200 baud, 8 data bits, no parity, one stop bit, and explain that bytes are currently received but not interpreted as commands.
- [x] Update the chat record to distinguish the new physical byte receiver from future command parsing and mode switching.
- [x] Run `git diff --check` and inspect the final diff to confirm only Stage 9 UART wiring and documentation changed; confirm `uart0_rx` is on P14 and the existing `mem_dq[3]` assignment remains on L8.
- [x] Leave hardware simulation and PDS rebuild for a turn where the user asks for verification.

## Self-Review

- Spec coverage: physical P14 input, synchronizer, 115200/8-N-1 decoding, valid-byte pulse, bad-stop handling, reset behavior, PDS source integration, and separation from interpolation controls are covered by Tasks 1–3.
- Pin consistency: the board UART RX input is P14; L8 remains the DDR data pin. Do not copy the nested DDR self-test's unrelated UART pin mapping.
- Scope: no command protocol, TX path, interpolation mux, angle update, FIFO, or Stage 8 change is included.
- Verification: the plan includes static integration checks; simulation and PDS rebuild are intentionally deferred unless the user requests verification.

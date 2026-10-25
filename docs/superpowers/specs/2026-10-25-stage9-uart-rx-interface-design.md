# Stage 9 UART RX Byte Interface Design

## Goal

Add a physical UART receive path to the Stage 9 Catmull–Rom project so a PC can later send control bytes through the Pangu 200 Pro+ board's built-in USB-UART bridge. This change establishes the serial byte boundary only; it does not select interpolation modes or update homography parameters.

## Board and project evidence

- The board is the Pangu 200 Pro+ / PG2L200H, using the CP2102 USB-UART bridge.
- The board manual maps `UART0_RX` to FPGA pin `P14` and `UART0_TX` to `K19`: [Pangu 2L200H board manual](https://www.meyesemi.com/upload/202506161410082.pdf).
- Stage 9's top-level FDC does not yet assign UART pins. `P14` is unused by the current top-level design. `L8` is already assigned to `mem_dq[3]`, so the UART pin map in the embedded DDR self-test FDC must not be copied into this top-level project.
- Stage 9 already routes `core_clk` (125 MHz DDR system clock) and `ddr_init_done` to the frame subsystem; these are available for the receiver clock and reset release.

## Proposed architecture

```text
PC COM port
    │ USB
    ▼
CP2102 on Pangu 200 Pro+
    │ UART0_RX, 115200 baud, 8-N-1, idle high
    ▼
FPGA P14 → two-flop synchronizer → UART RX sampler
    │ byte_data[7:0], byte_valid pulse, frame_error pulse
    ▼
Future packet parser / command decoder
```

### UART receiver module

Add `source/rtl/control/uart_rx_8n1.sv` with parameters `CLK_HZ` (default 125,000,000) and `BAUD_RATE` (default 115,200). It will synchronize the asynchronous RX pin, detect the start bit, sample eight LSB-first data bits near each bit center, and validate the stop bit.

Outputs:

- `byte_data[7:0]`: most recently received byte.
- `byte_valid`: one `core_clk` cycle for each byte with a valid stop bit.
- `frame_error`: one `core_clk` cycle when a candidate byte has a bad stop bit; that byte is discarded and does not assert `byte_valid`.

The receiver resets while `ddr_init_done` is low. The UART line is idle high. No receive FIFO or backpressure is included: at 115200 baud, valid-byte pulses are separated by thousands of 125 MHz cycles, and the later parser must consume each pulse.

### Top-level and pin constraint

- Add top-level input `uart0_rx`.
- Assign it to `P14`, `LVCMOS33`, with a weak pull-up if supported by the board's existing constraint convention.
- Instantiate the receiver in `core_clk` domain and release reset from `ddr_init_done`.
- Add the RTL file to the Stage 9 PDS source list.
- Keep `uart_rx_valid`, data, and frame-error diagnostics as internal signals for later parser integration.

## Explicit scope boundaries

- Do not add UART TX on `K19` in this increment.
- Do not define framing bytes, command IDs, CRC, timeouts, acknowledgements, or host software.
- Do not connect received bytes to `angle_cfg_valid` or interpolation selection. The current Catmull–Rom path remains unchanged.
- Do not modify Stage 8 or other project stages.

## Acceptance criteria

- The Stage 9 top-level has a constrained `uart0_rx` input on P14 and the RX module is included in the PDS project.
- Valid 8-N-1 bytes produce exactly one-cycle `byte_valid` with correct LSB-first byte ordering.
- Bad stop bits produce a one-cycle `frame_error`, with no valid-byte pulse.
- Asynchronous input is synchronized before the sampling state machine.
- The serial interface remains isolated from image-processing behavior until a future packet parser is designed.

## Verification plan

- Review the PDS source list, top-level port, P14 electrical attributes, and unchanged Stage 9 image datapath connections.
- If simulation or board verification is later requested, exercise multiple byte values, back-to-back frames, reset during idle, and bad stop-bit handling at the configured clock and baud rate.

## Self-review

- No command protocol or interpolation-mode behavior is implied by the byte receiver.
- The physical RX pin is sourced from the board manual, not guessed from the nested DDR self-test pin map.
- The serial clock domain is explicitly the existing 125 MHz `core_clk`; the external RX line is synchronized before use.
- Receive error and valid-byte behavior are defined, while FIFO/backpressure is excluded and documented.

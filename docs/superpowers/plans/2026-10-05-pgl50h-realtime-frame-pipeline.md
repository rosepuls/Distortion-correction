# PGL50H Realtime Frame Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the PGL50H board top continuously capture, correct, and display 720p30 frames with frame-safe input/output ping-pong storage.

**Architecture:** A core-clock frame scheduler owns input-complete, processing and output-ready events. A display-bank CDC switch applies completed output only at output-frame boundaries. Transaction-locking DDR arbiters replace the existing mutually-exclusive source muxes so capture, correction and display can make progress concurrently.

**Tech Stack:** SystemVerilog, PGL50H DDR3/HDMI reference IP, Vivado XSim, existing Python image assets.

## Global Constraints

- Keep `ddrphy_clkin` at 100 MHz and 1280×720@30 timing.
- Keep full-frame random source access and all existing fixed-point results unchanged.
- Keep generated XSim files in `xsim.dir`; the 720p image regression intentionally overwrites `result/sim_assets/cache_full_chain_1280x720/`.
- Do not downgrade real synchronous paths with global timing exceptions.
- Run each new test RED before its implementation and retain explicit `TEST_PASS:` markers.

---

### Task 1: Frame-scheduler contract

**Files:**
- Create: `rtl/board/pgl50h/realtime_frame_scheduler.sv`
- Create: `sim/tb_realtime_frame_scheduler.sv`
- Create: `sim/run_realtime_frame_scheduler.ps1`

**Interfaces:**
- Consumes: `input_frame_done`, `input_frame_bank`, `algo_frame_done`, `output_frame_done`, `display_bank_core`.
- Produces: one-cycle `process_start`, stable `process_input_bank`, stable `process_output_bank`, `output_ready_toggle`, `output_ready_bank`, `input_overrun`.

- [ ] Write a test that completes input banks 0, 1 and 0 with matching algorithm/output completions and asserts three starts, alternating output banks, and one ready toggle per completed result.
- [ ] Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\run_realtime_frame_scheduler.ps1`; it must fail because the scheduler does not exist.
- [ ] Implement the scheduler with latched bank ownership and completion flags.
- [ ] Re-run the scheduler test and require `TEST_PASS: realtime_frame_scheduler`.

### Task 2: Locked DDR client arbitration

**Files:**
- Create: `rtl/board/pgl50h/ddr_two_client_arbiter.sv`
- Create: `sim/tb_ddr_two_client_arbiter.sv`
- Create: `sim/run_ddr_two_client_arbiter.ps1`

**Interfaces:**
- Consumes: two command-valid/request-data client interfaces and one controller command/data interface.
- Produces: exactly one owner from command acceptance until done, and routes all return data/handshake signals only to that owner.

- [ ] Write a test in which client 0 and client 1 request overlapping transactions while controller ready/data-valid are delayed; assert that command, data and done never move to the wrong client.
- [ ] Run the arbiter test and verify it fails because the arbiter is absent.
- [ ] Implement read and write locking modes with display-read priority and rotating write grant after every completed transaction.
- [ ] Re-run the arbiter test and require `TEST_PASS: ddr_two_client_arbiter`.

### Task 3: Dynamic output-frame bases and display-boundary swap

**Files:**
- Modify: `rtl/board/pgl50h/algorithm_frame_writer.sv`
- Modify: `rtl/board/pgl50h/ddr3_frame_reader.sv`
- Modify: `sim/tb_algorithm_frame_writer.sv`
- Modify: `sim/tb_ddr3_frame_reader.sv`

**Interfaces:**
- `algorithm_frame_writer.frame_base_addr` is latched at output SOF and applies to all burst addresses for that frame.
- `ddr3_frame_reader.frame_base_addr` is latched at display frame start and applies to all read bursts for that displayed frame.

- [ ] Add a writer test that changes the requested next-frame base during a frame and asserts all current-frame command addresses retain the original base.
- [ ] Add a reader test that changes the requested next-frame base during active pixels and asserts current-frame read commands retain the original base.
- [ ] Run both tests to observe the expected missing-port/old-address failure.
- [ ] Add the latched base interfaces and make the tests pass.

### Task 4: Board-top continuous pipeline integration

**Files:**
- Modify: `rtl/board/pgl50h/pgl50h_board_top.sv`
- Modify: `boards/pgl50h/pds/pgl50h_rtl_synth/impl.tcl`
- Modify: `sim/run_pgl50h_board_top_compile.ps1`
- Modify: `sim/tb_pgl50h_board_top_compile.sv`

**Interfaces:**
- `realtime_frame_scheduler` receives existing input-frame and output completion events.
- Input write stays enabled after DDR/HDMI readiness; Cache read, display read, input write and output write use locked arbiters.
- Output-ready toggle crosses to the video domain and bank selection changes only at `video_mode_720p30.frame_start`.

- [ ] Extend the board structural test to stimulate two input-frame-complete events and assert a second processing start while display remains enabled.
- [ ] Run the board compile test to confirm it fails against the one-shot wiring.
- [ ] Integrate the scheduler, two input bases, two output bases, write/read arbiters, and display bank CDC.
- [ ] Re-run the structural test and require `TEST_PASS: pgl50h_board_top_compile` plus continuous-frame assertions.

### Task 5: Regression and image artifact refresh

**Files:**
- Test: `sim/run_realtime_frame_scheduler.ps1`
- Test: `sim/run_ddr_two_client_arbiter.ps1`
- Test: `sim/run_720p30_throughput.ps1`
- Test: `sim/run_mes50hp_top_cache_image_720p.ps1`
- Test: `sim/run_pgl50h_board_top_compile.ps1`
- Generated: `result/sim_assets/cache_full_chain_1280x720/`

- [ ] Run all scheduler/arbiter and pre-existing 720p30 regressions from PowerShell with `-NoProfile`.
- [ ] Confirm the image test reports 921,600 outputs, a pixel-perfect frame comparison and overwrites the existing RTL/golden/comparison image artifacts.
- [ ] Confirm 720p30 processing remains within 2,500,000 core cycles.
- [ ] Record command output and stop if any old functional or throughput regression fails.

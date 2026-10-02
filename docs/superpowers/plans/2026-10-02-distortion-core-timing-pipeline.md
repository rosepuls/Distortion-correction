# Distortion Core Timing Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan.

**Goal:** Convert the optimized distortion mapper into a 13-cycle, one-coordinate-per-clock, bit-exact pipeline that removes the current PGL50H normalization, tangential, and source-coordinate critical paths.

**Architecture:** Add S1C between S0 and S1 for centered-coordinate/inverse-focal registers, then register full-width radial/tangential products, quantized tangential terms, tangential sums, distorted sums, focal products, and final Q19 source coordinates in separate stages. Register `coordinate_split` outputs on the thirteenth edge. Propagate valid/SOF/EOL and required intrinsics through every stage.

**Tech Stack:** SystemVerilog RTL, XSim (`xvlog`, `xelab`, `xsim`), PowerShell run scripts, Pango Design Suite for user-run synthesis/place-and-route.

---

### Task 1: Lock the expected latency in tests

**Files:**
- Modify: `sim/tb_distortion_core_optimized.sv`
- Create: `sim/tb_distortion_core_optimized_stream.sv`
- Create: `sim/run_distortion_core_optimized.ps1`

1. Change the golden-vector test expectation from 7 to 12 clocks.
2. Add a streaming scoreboard that drives identity-mapping coordinates on consecutive clocks, inserts bubbles, checks SOF/EOL alignment, and starts a second frame.
3. Make the runner use only `xsim.dir/distortion_core_optimized_unit` for generated simulator files.
4. Run the tests against the old RTL and record the expected latency failures.

### Task 2: Add S4 and S5 product boundaries

**File:**
- Modify: `rtl/distortion/distortion_core_optimized.sv`

1. Replace the old final Stage 4 registers with registers for radial products, `p1*xy`, `p2*xy`, and both tangential bases.
2. Add the next stage for both tangential-base products and the original quantized radial/XY terms.
3. Propagate calibration intrinsics and metadata alongside the payload.

### Task 3: Add tangential and distorted-coordinate boundaries

**File:**
- Modify: `rtl/distortion/distortion_core_optimized.sv`

1. Register the saturated tangential X/Y sums.
2. Register the saturated radial-plus-tangential distorted X/Y sums.
3. Preserve the exact existing S21 saturation order.

### Task 4: Add source-coordinate and split boundaries

**File:**
- Modify: `rtl/distortion/distortion_core_optimized.sv`

1. Register the signed 45-bit focal products.
2. Register the shifted focal products plus shifted principal points as signed 64-bit Q19 coordinates.
3. Feed those registers to `coordinate_split` and register all output fields on the next edge.
4. Reset every added payload and metadata register explicitly.

### Task 5: Prove bit accuracy and streaming behavior

**Files:**
- Test: `sim/tb_distortion_core_optimized.sv`
- Test: `sim/tb_distortion_core_optimized_stream.sv`

1. Run the optimized-core test script.
2. Confirm all 25 golden vectors pass.
3. Confirm the streaming test passes back-to-back, bubble, marker, and frame-change cases.
4. Inspect warnings for width/sign mistakes rather than accepting a pass with suspicious truncation warnings.

### Task 6: Run integration regression

**Files:**
- Test: `sim/run_mes50hp_top_image.ps1`
- Test: `sim/run_pgl50h_board_top_compile.ps1`

1. Run the image-level top simulation and compare its output to the existing golden result.
2. Run the board-top compile/elaboration simulation.
3. Run `git diff --check` on the changed files.
4. Report that PDS must be rerun by the user and identify the expected timing paths to inspect.

## Execution Result

- Red phase confirmed: the previous 7-cycle RTL failed both 12-cycle tests.
- Golden-vector regression: 25/25 vectors passed after the 13-cycle refactor.
- Streaming regression: seven valid coordinates passed with consecutive inputs, bubbles, SOF/EOL, and a second frame configuration at 13-cycle latency.
- Image integration: 49,152/49,152 RGB pixels matched the fixed-point golden frame.
- Board-top XSim compile/elaboration regression passed.
- Remaining external step: rerun PDS synthesis and place-and-route for the added S1C register, then inspect `ddrphy_clkin` setup WNS/TNS and the worst path endpoints.

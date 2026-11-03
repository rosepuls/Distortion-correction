# Stage 12 Super-Resolution Feasibility Implementation Plan

> **For agentic workers:** Execute this plan inline with the `executing-plans` skill, task by task. Use TDD for behavioral RTL changes.

**Goal:** Create an isolated Stage 12 FPGA project based on the Stage 5 identity DDR design that scales 1280×720 input to 1920×1080 at 30 Hz and applies bilinear interpolation with bounded adaptive edge sharpening.

**Architecture:** Copy the Stage 5 identity-coordinate DDR project into a new `stage12_...` project without generated PDS outputs. Separate source-frame and output-frame dimensions, map each 1080p output coordinate into the 720p source, and add a pipelined adaptive sharpening step to the existing 2×2 bilinear sample path. Keep Brown distortion correction, angle correction, general image enhancement, and UART outside this feasibility stage.

**Tech Stack:** SystemVerilog/Verilog, Pango PDS 2022.2-SP6.4, Vivado Simulator 2020.2, PowerShell, Python standard library for a fixed-point reference model.

## Global Constraints

- Create all project changes under `fpga/project/stage12_720p_to_1080p30_bilinear_adaptive_sharpen_test/`; do not edit Stage 5, Stage 8, Stage 10, or Stage 11 sources.
- The input frame remains 1280×720; the output frame and HDMI timing are 1920×1080 at 30 Hz.
- Reuse the existing 2×2 DDR tile-cache neighbor fetch; the sharpening stage must not issue additional DDR reads.
- Preserve RGBX8888 word format, frame-pool slot separation, fail-stop frame handling, and ready/valid metadata alignment.
- Keep the Stage 12 test project free of Brown correction, angle correction, Stage 11 LUT enhancement, and UART protocol/control.
- Do not claim board feasibility from simulation or PDS timing alone; distinguish RTL simulation, PDS timing, and physical board validation.

---

### Task 1: Copy the clean identity DDR project

**Files:**
- Create: `fpga/project/stage12_720p_to_1080p30_bilinear_adaptive_sharpen_test/` from `fpga/project/stage5_identity_ddr/`
- Create: `fpga/project/stage12_720p_to_1080p30_bilinear_adaptive_sharpen_test/README.md`
- Create: `fpga/project/New-Stage12SuperResolutionProject.ps1`

- [x] Copy Stage 5 project sources, IP, constraints, and PDS project description while excluding generated build folders, bitstreams, logs, and locks.
- [x] Change the PDS source references to point only at the Stage 12 local source tree and add a project-local simulation/build entry point.
- [x] Verify that Stage 5 and other existing projects have no source-file content changes and that the copied Stage 12 PDS source list resolves locally.

### Task 2: Specify and test the 720p-to-1080p coordinate mapping

**Files:**
- Create: `fpga/project/stage12_720p_to_1080p30_bilinear_adaptive_sharpen_test/source/rtl/correction/scale_3_2_mapper.sv`
- Create: `fpga/project/stage12_720p_to_1080p30_bilinear_adaptive_sharpen_test/sim/scale_3_2_mapper_tb.sv`
- Create: `fpga/project/stage12_720p_to_1080p30_bilinear_adaptive_sharpen_test/sim/Run-ScaleMapper.ps1`

- [x] Write a failing mapper test for the center-aligned 3:2 output-to-input mapping: `src = (dst + 0.5) × 2/3 − 0.5`, rounded to signed Q16.16; check the first, middle, and last output coordinates on both axes.
- [x] Run the test and confirm the expected missing-module failure.
- [x] Implement an elastic one-pixel-per-cycle mapper that accepts 12-bit destination coordinates and emits signed Q16.16 source coordinates plus unchanged frame metadata.
- [x] Run the mapper test to confirm bounds, rounding, reset, and backpressure behavior.

### Task 3: Define and test adaptive bilinear sharpening

**Files:**
- Create: `fpga/project/stage12_720p_to_1080p30_bilinear_adaptive_sharpen_test/source/rtl/correction/adaptive_bilinear_sharpener.sv`
- Create: `fpga/project/stage12_720p_to_1080p30_bilinear_adaptive_sharpen_test/sim/adaptive_bilinear_sharpener_tb.sv`
- Create: `fpga/project/stage12_720p_to_1080p30_bilinear_adaptive_sharpen_test/sim/Run-AdaptiveSharpener.ps1`

- [x] Define a deterministic fixed-point operation for each RGB channel: compute the existing Q16 bilinear value and the rounded mean of the same four neighbors; when that channel's 2×2 contrast exceeds a parameterized threshold, add a bounded `1/4 × (bilinear − mean)` correction; clamp the result to the local channel minimum and maximum. Preserve the RGBX low byte as zero.
- [x] Write RTL cases for a constant patch (unchanged), a below-threshold ramp (unchanged), a high-contrast edge, local min/max clamping, fractional weights, and ready/valid metadata stability during backpressure.
- [x] Run the directed simulations and confirm corrected edge values, clipping, and metadata alignment.
- [x] Implement the arithmetic in elastic pipeline stages with one accepted sample per cycle after pipeline fill; leave the existing Stage 5 interpolator untouched.
- [x] Run the adaptive interpolator test and confirm all directed cases pass.

### Task 4: Integrate the Stage 12 1080p output frame path

**Files:**
- Create in Stage 12 only: `source/rtl/correction/scale_3_2_coordinate_pipeline.sv`
- Create in Stage 12 only: `source/rtl/correction/stage12_super_resolution_pipeline.sv`
- Modify in Stage 12 only: `source/rtl/memory/frame_identity_transform_engine.sv`
- Modify in Stage 12 only: `source/rtl/fram_buf.v`
- Modify in Stage 12 only: `source/rtl/sync_vg.v`
- Modify in Stage 12 only: `source/rtl/HDMI_IN_DDR3_HDMI_OUT_top.v`
- Modify in Stage 12 only: `source/rtl/frame_pool_address.v`
- Modify in Stage 12 only: `HDMI_IN_DDR3_HDMI_OUT.pds`
- Create: `sim/stage12_full_frame_tb.sv`
- Create: `sim/Run-Stage12FullFrame.ps1`

- [x] Write a full-frame engine test for 21-bit output IDs, 14-bit burst count, 2,073,600-pixel completion, source/output address bounds, and write-drain publication.
- [x] Separate capture dimensions (1280×720) from processed/display dimensions (1920×1080); keep each three-slot DDR frame allocation within its 2²²-word slot.
- [x] Generate one 3:2 output-to-source coordinate per destination pixel, feed the existing 2×2 cache and the new adaptive interpolator, and write the complete 1080p frame to the independent output pool.
- [x] Update HDMI output timing to 1920×1080p30 (`H_TOTAL=2200`, `V_TOTAL=1125`, active 1920×1080) while retaining the existing 74.25 MHz pixel clock.
- [x] Run targeted mapper, interpolator, frame-engine, and full-frame tests; verify all output addresses and beats stay inside the selected output slot and that frames publish only after drain.

### Task 5: Synthesize, route, and record feasibility evidence

**Files:**
- Modify: `fpga/project/stage12_720p_to_1080p30_bilinear_adaptive_sharpen_test/README.md`
- Create: `docs/results/stage12-super-resolution-feasibility.md`

- [x] Run the Stage 12 PDS compile, synthesis, placement, routing, timing, and bitstream flow using only the Stage 12 project files.
- [x] Record actual PDS exit status, LUT/register/DRM use, setup WNS/TNS, and any failed endpoints; do not substitute Stage 5/8 timing or throughput results.
- [x] State that board-level 1080p30 display and visual A/B validation remain pending until the matching Stage 12 `.sbit/.smsk` pair is programmed and measured.
- [x] Recheck the copied project boundaries, PDS source list, project documentation, and all Stage 12 test results before reporting feasibility.

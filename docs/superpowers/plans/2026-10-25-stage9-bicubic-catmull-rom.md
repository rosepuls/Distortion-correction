# Stage 9 Catmull–Rom Bicubic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a separately buildable Stage 9 Catmull–Rom bicubic image-sampling project based on Stage 8, with verified 4×4 sampling and a same-build Fabric Debugger FIC for board frame-rate measurements.

**Architecture:** Preserve Stage 8 unchanged. Stage 9 will use the existing homography and fractional Brown coordinate path, a strict-border 4×4 sample planner and cache-backed neighbor gatherer, and a pipelined separable Catmull–Rom RGBX8888 interpolator. A host fixed-point model and RTL simulations establish numerical and streaming behavior before the Stage 9 PDS project is built; the build script verifies timing and the paired `.sbit/.fic` artifacts.

**Tech Stack:** SystemVerilog/Verilog, Vivado Simulator 2020.2, Python, PowerShell, Pango PDS 2022.2-SP6.4, Fabric Debugger.

## Global Constraints

- Keep `fpga/project/stage8_angle_correction/` unchanged.
- Use Catmull–Rom / Keys `a=-0.5`; use signed Q16.16 input coordinates and RGBX8888 pixels.
- Mark geometry valid only when all 16 neighbors are in bounds; otherwise emit black while preserving stream metadata.
- Preserve `valid/ready`, pixel/frame/parameter identifiers, and `sof/eol/eof` ordering through all new elastic stages.
- Name the first implementation project `fpga/project/stage9_bicubic_catmull_rom/` and provide a matching `.fic` for every generated test-project `.sbit`.
- Do not claim board frame rate or image-quality results before the user measures the generated paired artifacts on hardware.

---

### Task 1: Add the fixed-point software reference

**Files:**
- Create: `host/reference/bicubic_interpolator_reference.py`
- Create: `host/reference/test_bicubic_interpolator_reference.py`

**Interfaces:**
- Produces `catmull_rom_weights_q(...)` for two Q16.16 fractional coordinates and `bicubic_interpolate_rgbx8888(...)` for a 4×4 RGBX8888 neighborhood.
- Defines the coefficient format, signed intermediate widths, rounding, clamping, and output-byte rule used by the RTL.

- [ ] Write tests for exact integer-coordinate reproduction, selected fractional Catmull–Rom vectors, constant-image preservation, RGB saturation, and ignored RGBX low bytes.
- [ ] Run only the new tests and confirm they fail because the reference functions do not exist.
- [ ] Implement the minimal fixed-point model and document its rounding and saturation semantics in the module docstring.
- [ ] Run the new tests and confirm they pass.

### Task 2: Create the Stage 9 project scaffold and planner tests

**Files:**
- Create: `fpga/project/stage9_bicubic_catmull_rom/` as a full copy of the committed Stage 8 project, excluding generated PDS outputs.
- Create: `fpga/project/stage9_bicubic_catmull_rom/sim/bicubic_sample_planner_tb.sv`
- Create: `fpga/project/stage9_bicubic_catmull_rom/sim/Run-Stage9BicubicPlanner.ps1`
- Create: `fpga/project/stage9_bicubic_catmull_rom/source/rtl/correction/bicubic_sample_planner.sv`

**Interfaces:**
- Planner accepts signed Q16.16 source coordinates and the existing frame/pixel metadata; emits four x positions, four y positions, a 16-bit neighbor-valid mask, geometry-valid, fractional x/y, and unchanged metadata.
- The Catmull–Rom stencil is `[floor(x)-1, floor(x), floor(x)+1, floor(x)+2] × [floor(y)-1, floor(y), floor(y)+1, floor(y)+2]`.

- [ ] Add failing planner cases for integer and fractional coordinates, all four image edges, negative coordinates, and ready/valid stalls.
- [ ] Run the planner simulation and confirm it fails because the Stage 9 planner is absent.
- [ ] Copy Stage 8 into the Stage 9 directory, excluding generated output folders, logs, and ignored build products; verify the tracked PDS/IP/source baseline matches Stage 8 before edits.
- [ ] Implement the planner with strict full-4×4 border validity, black-border mask behavior, and metadata preservation.
- [ ] Run the planner simulation and confirm it passes.

### Task 3: Gather all 16 pixels through the Stage 9 DDR tile cache

**Files:**
- Create: `fpga/project/stage9_bicubic_catmull_rom/source/rtl/memory/cached_bicubic_neighbor_reader.sv`
- Create: `fpga/project/stage9_bicubic_catmull_rom/sim/cached_bicubic_neighbor_reader_tb.sv`
- Create: `fpga/project/stage9_bicubic_catmull_rom/sim/Run-Stage9BicubicReader.ps1`

**Interfaces:**
- Consumes the Stage 9 planner's 4×4 coordinates/mask and the existing DDR read arbitration signals.
- Produces a 16-pixel ordered RGBX8888 vector, fractional weights, validity, metadata, and the existing reader diagnostics.

- [ ] Add failing reader checks for a 4×4 block contained in one tile, blocks crossing horizontal and vertical tile boundaries, cache misses/refills, black-border invalid samples, response backpressure, and source-frame changes.
- [ ] Run the reader simulation and confirm the missing Stage 9 reader is the expected failure.
- [ ] Implement the reader/cache request sequencing using the existing Stage 8 tile cache and row DDR adapter contracts; preserve ordering and ensure a frame-slot change invalidates stale cache responses.
- [ ] Run the reader simulation and confirm the returned 16 samples match a deterministic source image for every tested tile alignment.

### Task 4: Add the elastic Catmull–Rom interpolation RTL

**Files:**
- Create: `fpga/project/stage9_bicubic_catmull_rom/source/rtl/correction/pipelined_catmull_rom_interpolator.sv`
- Create: `fpga/project/stage9_bicubic_catmull_rom/sim/catmull_rom_interpolator_tb.sv`
- Create: `fpga/project/stage9_bicubic_catmull_rom/sim/Run-Stage9CatmullRomInterpolator.ps1`

**Interfaces:**
- Consumes 16 RGBX8888 samples, Q16.16 fractional coordinates, a 16-bit validity mask, geometry validity, and the standard pixel/frame/version/boundary metadata.
- Produces one RGBX8888 result and the same metadata under elastic `valid/ready` flow control.

- [ ] Add failing RTL checks against the Task 1 software reference for integer/fractional vectors, negative-weight cases, rounding/saturation, invalid geometry, and randomized output stalls.
- [ ] Run the RTL simulation and confirm it fails because the interpolator is absent.
- [ ] Implement the separable horizontal then vertical Catmull–Rom pipeline with signed products and the agreed fixed-point rounding/clamping behavior.
- [ ] Run the RTL simulation; require every output pixel and metadata field to match the reference under stalls.

### Task 5: Connect Stage 9's transform pipeline and whole-frame simulation

**Files:**
- Modify: `fpga/project/stage9_bicubic_catmull_rom/source/rtl/correction/stage5_identity_pipeline.sv`
- Modify: `fpga/project/stage9_bicubic_catmull_rom/source/rtl/memory/frame_identity_transform_engine.sv`
- Modify: `fpga/project/stage9_bicubic_catmull_rom/HDMI_IN_DDR3_HDMI_OUT.pds`
- Create: `fpga/project/stage9_bicubic_catmull_rom/sim/stage9_bicubic_frame_tb.sv`
- Create: `fpga/project/stage9_bicubic_catmull_rom/sim/Run-Stage9BicubicFrame.ps1`

**Interfaces:**
- Keep the existing homography parameter bank, homography mapper, fractional Brown mapper, frame ownership, DDR write engine, and diagnostic counter semantics.
- Replace only the 2×2 planner/reader/bilinear chain with the tested Stage 9 4×4 planner/reader/Catmull–Rom chain.

- [ ] Add a failing full-frame test for at least one deterministic 1280×720 source pattern and identity homography, checking all output addresses/data, frame completion, black borders, and no metadata mismatch.
- [ ] Run the test and confirm the current Stage 9 chain is not yet connected.
- [ ] Connect the tested modules and update the PDS source list without changing unrelated video, pin, IP, or timing configuration.
- [ ] Run the full-frame simulation and confirm exact frame accounting, expected output pixels, and successful drain/publication.

### Task 6: Build, measure resources, and deliver the matching FIC

**Files:**
- Create: `fpga/project/stage9_bicubic_catmull_rom/Build-Stage9Bicubic.ps1`
- Modify: `fpga/project/stage9_bicubic_catmull_rom/configure_angle_correction.py`
- Modify: `fpga/project/stage9_bicubic_catmull_rom/README.md`
- Modify: `fpga/project/stage9_bicubic_catmull_rom/README_JTAG.md`
- Create: `docs/results/stage9-bicubic-catmull-rom.md`

**Interfaces:**
- The build script accepts the PDS shell path and optional finalize-only mode, and emits the project `.sbit` plus matching `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic`.
- The FIC map includes input VSYNC, complete input publication, processing completion, display-new-frame, READY overwrite, error flags, recent/max frame cycles, coordinate stalls, cache misses/fill cycles, and read/write waits within the 256-channel limit.

- [ ] Add build-script checks for all 256 FIC channel definitions, required signals, bitstream, timing report, and `All Constraints Met`; ensure the copied `.fic` hash matches the synthesis FIC used for that build.
- [ ] Run targeted software/RTL/planner/reader/full-frame simulations and record each command/result.
- [ ] Run the Stage 9 PDS synthesis, Fabric Debugger insertion, place/route, timing, and bitstream flow.
- [ ] If the build succeeds, verify the `.sbit` and `.fic` exist, compute both SHA-256 hashes, and record timing/resource results. If timing or routing fails, preserve the log/report and revise the Stage 9 design without touching Stage 8.
- [ ] Update the README with the exact program/import steps and state that only this project's `.sbit/.fic` pair measures this project's counters.

## Self-Review

- Spec coverage: algorithm kernel, fixed-point parity, strict 4×4 bounds, cache/DDR neighbor reads, stream metadata and stalls, Stage 8 preservation, Stage 9 naming, full-frame verification, and paired FIC delivery are assigned to Tasks 1–6.
- Placeholder scan: no TODO/TBD or unspecified test command remains; the PDS shell location is supplied by the existing Stage 8 build convention.
- Type/interface consistency: planner emits the coordinate/validity data consumed by the reader; the reader returns the 16 samples and metadata consumed by the interpolator; the integration task replaces the existing bilinear path with these interfaces.

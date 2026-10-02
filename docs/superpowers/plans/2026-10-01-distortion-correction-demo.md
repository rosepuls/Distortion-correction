# Distortion Correction Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate a synthetic camera-distorted RGB frame, correct it through the real RTL chain, and produce an isolated visual comparison.

**Architecture:** Python iteratively inverts the Brown-Conrady mapping to create a distorted DDR source frame from a straight checkerboard. The existing RTL pipeline then performs the normal reverse-map correction, while the bit-accurate Python model creates the comparison oracle from the same distorted input.

**Tech Stack:** Python 3, NumPy, Pillow, SystemVerilog, Vivado XSim 2020.2, PowerShell.

## Global Constraints

- Keep camera and distortion parameters identical to the existing 256×192 regression.
- Do not modify the verified RTL arithmetic chain.
- Put final artifacts only in `result/sim_assets/correction_full_chain_256x192/`.
- Put XSim-generated files only in `xsim.dir/distortion_correction_image/`.
- Preserve all unrelated working-tree changes.

---

### Task 1: Inverse-map distorted input generator

**Files:**
- Create: `tests/test_generate_distorted_input.py`
- Create: `software/sim_assets/generate_distorted_input.py`

**Interfaces:**
- Produces `inverse_distortion_map(width, height, camera, iterations=12)` returning Q13.19 source maps.
- Produces `generate_distorted_input(image, camera)` returning an RGB NumPy frame.

- [x] Write tests proving identity parameters preserve interior coordinates and negative radial distortion maps a distorted edge pixel farther from the optical center in the clean source.
- [x] Run the focused test and verify it fails because the module is absent.
- [x] Implement iterative inversion and fixed-point bilinear sampling.
- [x] Run focused and existing distortion-model tests.

### Task 2: Correction-direction Testbench

**Files:**
- Create: `sim/tb_distortion_correction_image.sv`

**Interfaces:**
- Loads `distorted_input_256x192.mem` into `ddr_behavior_model`.
- Compares `distortion_image_pipeline` output against `golden_corrected_256x192.mem`.

- [x] Create the Testbench with camera constants identical to the generator.
- [x] Compile and elaborate it with the already verified RTL chain.
- [x] Require correct RGB, SOF, EOL, and exactly 49,152 outputs.

### Task 3: Isolated full-frame runner and visual panel

**Files:**
- Create: `software/sim_assets/create_correction_panel.py`
- Create: `sim/run_distortion_correction_image.ps1`
- Modify: `software/sim_assets/README.md`

**Interfaces:**
- Generates standard, distorted, Golden, RTL, and comparison PNG/MEM assets.
- Runs XSim only from `xsim.dir/distortion_correction_image/`.

- [x] Generate standard and distorted frames in the dedicated result directory.
- [x] Generate the fixed-point Golden correction from the distorted frame.
- [x] Run XSim, compare all RTL/Golden pixels, and convert outputs to PNG.
- [x] Build a four-panel `correction_comparison.png` and document the command.

### Task 4: Final verification

**Files:**
- Verify all Task 1–3 outputs.

**Interfaces:**
- Produces repeatable evidence for functional correction and bit accuracy.

- [x] Run the complete correction script and require XSim plus frame-comparison PASS.
- [x] Run the full Python unit-test suite with zero failures.
- [x] Inspect `correction_comparison.png` and confirm the geometric direction.
- [x] Run `git diff --check` and preserve unrelated changes.

## Plan Self-Review

- The plan independently verifies inverse-map direction, RTL bit accuracy, and visible correction.
- All paths and camera constants are explicit and consistent.
- No unassigned implementation decisions remain.

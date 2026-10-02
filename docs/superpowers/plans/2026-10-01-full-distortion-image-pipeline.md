# Full Distortion Image Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify a 256×192 image simulation in which RTL calculates distortion coordinates and fetches/interpolates RGB pixels from the DDR behavior model.

**Architecture:** A new handshake wrapper accepts one raster marker only when both the distortion pipeline slot and Pixel Fetch are available. It connects `coordinate_gen`, `distortion_core`, `pixel_fetch_engine`, and `bilinear_interp`; the Testbench connects the wrapper to `ddr_behavior_model` and compares every output pixel with the Python fixed-point Golden frame.

**Tech Stack:** SystemVerilog, Vivado XSim 2020.2, Python 3, NumPy, Pillow, PowerShell.

## Global Constraints

- Use 256×192 RGB888 with a frame stride of 256 pixels.
- Use `fx=fy=180.0`, `cx=127.5`, `cy=95.5`, `k1=-0.25`, `k2=0.05`, `p1=0.001`, `p2=-0.001`.
- Store final artifacts only in `result/sim_assets/full_chain_256x192/`.
- Store all XSim-generated files only in `xsim.dir/distortion_image_pipeline/`.
- Preserve all existing user changes and generated assets.

---

### Task 1: Add the visual comparison helper

**Files:**
- Create: `tests/test_distortion_comparison_panel.py`
- Create: `software/sim_assets/create_comparison_panel.py`

**Interfaces:**
- Consumes: three same-sized RGB Pillow images.
- Produces: `create_comparison_panel(input_image, golden_image, rtl_image) -> Image.Image`.

- [x] Write a test asserting a 2×2 panel size and black difference tile for equal Golden/RTL images.
- [x] Run the test and verify import failure because the helper is absent.
- [x] Implement the minimal labeled 2×2 panel and amplified absolute-difference image.
- [x] Run the focused test and existing image-asset tests.

### Task 2: Add the RTL handshake wrapper and failing image Testbench

**Files:**
- Create: `sim/tb_distortion_image_pipeline.sv`
- Create: `rtl/distortion/distortion_image_pipeline.sv`

**Interfaces:**
- Consumes: raster `in_valid/in_ready/in_sof/in_eol`, camera configuration, and memory responses.
- Produces: memory requests and RGB888 `out_pixel/out_valid/out_sof/out_eol`.

- [x] Write the Testbench first, loading source and Golden MEM files and checking every output transaction.
- [x] Compile it before the wrapper exists and verify the expected missing-module failure.
- [x] Implement the one-coordinate-in-flight wrapper connecting the four existing RTL stages.
- [x] Compile and elaborate the complete chain.

### Task 3: Add isolated asset generation and one-command regression

**Files:**
- Create: `sim/run_distortion_image_pipeline.ps1`
- Modify: `software/sim_assets/README.md`

**Interfaces:**
- Consumes: existing image/vector generators, Testbench, and MEM-to-PNG tool.
- Produces: all final assets under `result/sim_assets/full_chain_256x192/` and XSim files under the dedicated run directory.

- [x] Generate the RGB input MEM and Python fixed-point Golden MEM in the new result folder.
- [x] Run XSim from the isolated run directory.
- [x] Compare RTL and Golden MEM files, convert both to PNG, and generate the four-panel PNG.
- [x] Document the single PowerShell command and output paths.

### Task 4: Verify the complete deliverable

**Files:**
- Verify all files from Tasks 1–3.

**Interfaces:**
- Consumes: the final scripts and RTL sources.
- Produces: evidence for functional completion.

- [x] Run `sim/run_distortion_image_pipeline.ps1` and require both XSim and frame-comparison PASS messages.
- [x] Run `py -m unittest discover -s tests -p 'test_*.py'` and require zero failures.
- [x] Inspect the final comparison PNG and verify all expected files are in the dedicated result folder.
- [x] Run `git diff --check` and report unrelated pre-existing worktree changes without modifying them.

## Plan Self-Review

- Every requirement in the approved design is covered by one task.
- File names, camera parameters, directory names, and interfaces are consistent across tasks.
- No placeholder behavior or deferred implementation remains.

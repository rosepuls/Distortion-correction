# Motion Video Super-Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evaluate and implement a compact 3:2 residual CNN candidate for 720p-to-1080p motion video, targeting at least 30 new processed frames per second.

**Architecture:** First build a software training/inference and video A/B path using an 8-bit quantized low-resolution luma CNN that predicts nine 3:2 phase residuals over a bicubic base. After quality and compute gates pass, copy the current Stage12 streaming project into an isolated candidate, then add line-buffered inference and phase reordering without changing the known-good project.

**Tech Stack:** Python/PyTorch for training and fixed-point reference; SystemVerilog and PDS 2022.2-SP6.4 for FPGA implementation; Vivado Simulator 2020.2 for RTL verification.

## Global Constraints

- Input remains RGBX8888 1280×720; output remains RGBX8888 1920×1080 at 60 Hz scanout.
- The acceptance throughput target is at least 30 new processed frames/s.
- Do not modify the existing Stage12 streaming project; develop in a separate copied project.
- Preserve frame ordering, frame ownership, valid/ready backpressure, and RGBX low-byte zero.
- Evaluate temporal flicker and false detail on complete motion clips, not isolated stills only.
- Do not claim target throughput until measured on the board with the matching bitstream/FIC.

---

### Task 1: Build paired motion-video evaluation set

**Files:**
- Create: `host/super_resolution/README.md`
- Create: `host/super_resolution/prepare_pairs.py`
- Create: `host/super_resolution/evaluate_video.py`
- Create: `host/super_resolution/metrics.py`

**Interfaces:** `prepare_pairs.py` accepts high-resolution video/image sequences and emits aligned 1080p reference / 720p degraded pairs. `evaluate_video.py` compares bilinear, current adaptive sharpening, DCCI, and model outputs and reports frame metrics plus temporal stability metrics.

- [ ] Record frame-size, frame-rate, color-order, and degradation metadata with each sequence.
- [ ] Split train/validation data by source clip to prevent neighboring-frame leakage.
- [ ] Implement metric reporting for Y-PSNR, SSIM, edge contrast, temporal gradient variation, and frame runtime.
- [ ] Verify evaluation on a small known clip and save a baseline report.

### Task 2: Train and quantize the 3:2 residual model

**Files:**
- Create: `host/super_resolution/model.py`
- Create: `host/super_resolution/train.py`
- Create: `host/super_resolution/export_int8.py`
- Create: `host/super_resolution/fixed_point_reference.py`

**Interfaces:** `model.py` maps an 8-bit luma frame to nine residual phases for each 2x2 source block. `export_int8.py` writes signed 8-bit weights and per-tensor scales. RTL bit-exact emulation remains a required follow-up before weight ROM generation.

- [ ] Implement the 8-channel stem, two depthwise-separable blocks, and nine-phase residual head.
- [ ] Train against paired motion clips with pixel, gradient, and bounded-residual losses.
- [ ] Export per-layer scales and signed 8-bit weights to a documented JSON/binary format.
- [ ] Compare floating and fixed-point outputs and report quality/runtime on held-out clips.

### Task 3: Establish algorithm gate

**Files:**
- Modify: `host/super_resolution/evaluate_video.py`
- Create: `host/super_resolution/reports/candidate-summary.md`

- [ ] Compare current bilinear/sharpener, DCCI, and quantized CNN on the same clips.
- [ ] Reject candidates with visible unstable texture, edge halos, or increased motion flicker.
- [ ] Record the selected model, model hash, quality deltas, and software throughput before FPGA work.

### Task 4: Create isolated FPGA candidate and map the stream interface

**Files:**
- Create: `fpga/project/stage12_1080p60_cnn_sr_test/` as a complete copy of `stage12_1080p60_streaming_linebuffer_test/`
- Modify in candidate only: `source/rtl/correction/stage12_super_resolution_pipeline.sv`
- Modify in candidate only: PDS project source list and `README.md`

- [ ] Copy source, simulation, PDS configuration, constraints, IP, and scripts; do not copy stale build outputs as candidate results.
- [ ] Document the signed weight format, activation format, accumulator width, rounding, saturation, and 3:2 phase ordering.
- [ ] Keep current RGBX and frame metadata interfaces stable; wire luma inference and chroma bilinear paths into a documented merge point.

### Task 5: Implement streaming fixed-point CNN

**Files:**
- Create in candidate: `source/rtl/correction/sr_luma_frontend.sv`
- Create in candidate: `source/rtl/correction/sr_depthwise_pointwise_block.sv`
- Create in candidate: `source/rtl/correction/sr_phase_head_3x2.sv`
- Create in candidate: `source/rtl/correction/sr_phase_reorder.sv`
- Create in candidate: `source/rtl/correction/sr_weights_rom.sv`
- Modify in candidate: `source/rtl/correction/stage12_super_resolution_pipeline.sv`

- [ ] Add elastic pipeline stages for luma, feature convolutions, phase residual output, and RGB merge.
- [ ] Add line storage for the network receptive field and three output phase rows.
- [ ] Preserve all metadata under stalls and emit exactly 2,073,600 pixels per output frame.
- [ ] Add a bypass control in the candidate for direct A/B comparison with current sharpening.

### Task 6: Verify, build, and measure

**Files:**
- Create: candidate `sim/sr_model_match_tb.sv`
- Modify: candidate `README_JTAG.md`
- Create: `docs/results/stage12-cnn-sr-feasibility.md`

- [ ] Compare RTL fixed-point outputs against the Python fixed-point reference on phase, border, saturation, and motion clips.
- [ ] Run full-frame simulation checking output count/order, row boundaries, backpressure, frame reset, DDR bounds, and write drain.
- [ ] Run complete PDS build and record LUT, FF, DRM, APM, clock slack, and matching bitstream/FIC hashes.
- [ ] Measure input-published, processed, and display-taken counters over a timed board interval; require at least 30 processed new frames/s.
- [ ] Compare the CNN candidate with the current Stage12 bitstream on the same motion clip and record temporal artifacts.

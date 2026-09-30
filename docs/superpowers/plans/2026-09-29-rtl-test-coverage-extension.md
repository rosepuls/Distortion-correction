# RTL Testbench Coverage Extension Plan

_Plan for extending the existing module testbenches in place; existing tests remain unchanged._

---

## 🎯 Goal

Add checks for stream bubbles, reset behavior, frame-marker propagation, and module-specific boundary values to the ten existing Vivado SystemVerilog testbenches without replacing their current test sequences.

## ⚙️ Constraints

- Preserve existing test vectors and PASS/FAIL behavior.
- Add test stimulus and assertions only to the current `sim/tb_*.sv` files unless an RTL defect is proven by a failing test.
- Keep all tests runnable with Vivado Simulator 2020.2 using `xvlog`, `xelab`, and `xsim`.
- Do not claim full-frame or multi-frame coverage unless the testbench sends two distinct frames and checks the second frame's start marker and output data.

## 📋 Tasks

### Task 1: Extend pixel-stream arithmetic and mapping testbenches

Files: `sim/tb_rgb2gray.sv`, `sim/tb_brightness_gain.sv`, `sim/tb_gamma_lut.sv`, `sim/tb_bilinear_interp.sv`.

- Add explicit bubble checks that expect `out_valid=0` and control markers deasserted.
- Add a second frame with different data and verify `out_sof`/`out_eol` alignment where those ports exist.
- Assert reset during operation, check outputs clear, then send a known sample after reset.
- Add module-relevant boundaries: RGB primary/black/white, brightness underflow/overflow, gamma bank/endpoint behavior, and bilinear `dx/dy` corners plus invalid coordinates.

### Task 2: Extend 3x3 and detection testbenches

Files: `sim/tb_gaussian_3x3.sv`, `sim/tb_sobel_3x3.sv`, `sim/tb_threshold.sv`, `sim/tb_morphology.sv`.

- Check output validity and relevant frame/line markers during valid samples and bubbles.
- Exercise another frame start, reset recovery, and input extremes or equality boundaries.
- Preserve the existing hand-calculated expected outputs and count every mismatch.

### Task 3: Extend spatial-buffer testbenches

Files: `sim/tb_line_buffer_3x3.sv`, `sim/tb_window_3x3.sv`.

- Add valid bubbles within and around line/frame boundaries.
- Send a second 3x2 frame with different pixels and check its first output windows/taps.
- Reset during a frame and verify stale row/column state is not reused.
- Check corners, right-edge flushing, synthetic rows, output counts, and marker positions.

### Task 4: Verify the additions

- Compile and run all ten testbenches with Vivado Simulator 2020.2.
- Require one `TEST_PASS: <module>` and no `TEST_FAIL` for each module.
- Run the available Python model tests; report any unavailable simulator or skipped test explicitly.

## Verification record

- Vivado Simulator 2020.2: `TEST_PASS` for `rgb2gray`, `brightness_gain`, `gamma_lut`, `bilinear_interp`, `gaussian_3x3`, `sobel_3x3`, `threshold`, `morphology`, `line_buffer_3x3`, and `window_3x3`.
- Python: `python -m pytest tests/test_preprocess_models.py -q` — 10 passed.
- Simulator runs used temporary directories; the existing project `xsim.dir` was not used or overwritten.

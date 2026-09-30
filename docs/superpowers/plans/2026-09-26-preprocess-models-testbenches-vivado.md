# Preprocess Models, Testbenches, and Vivado Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为十个基础图像 RTL 模块建立 Python golden model、独立自检 SystemVerilog Testbench，并使用 Vivado Simulator 2020.2 实际运行自动 PASS/FAIL。

**Architecture:** Python 模型放在 `software/models/`，每个 RTL 模块对应一个独立模型文件。`sim/tb_*.sv` 使用手工推导的固定向量进行独立自检，统一 PowerShell 脚本在临时可写目录中依次调用 `xvlog`、`xelab`、`xsim`，避免 Vivado 生成文件污染源码目录。

**Tech Stack:** Python 3、NumPy、SystemVerilog、Vivado Simulator 2020.2、PowerShell。

## Global Constraints

- 本阶段不创建 PDS 工程，也不生成 PDS 资源或时序报告。
- RTL 接口和算法逻辑不因测试基础设施而改变。
- 每个 `tb_*.sv` 必须自检并打印唯一的 `TEST_PASS` 或 `TEST_FAIL`。
- Vivado 生成的日志、快照和 `xsim.dir` 只能写入临时构建目录。
- 参考模型必须遵守 `numeric_spec.md` 和 `border_policy.md` 的截断、饱和与零填充规则。

---

### Task 1: Python Golden Models

**Files:**
- Create: `software/models/__init__.py`
- Create: `software/models/rgb2gray_model.py`
- Create: `software/models/brightness_gain_model.py`
- Create: `software/models/gamma_lut_model.py`
- Create: `software/models/bilinear_interp_model.py`
- Create: `software/models/line_buffer_3x3_model.py`
- Create: `software/models/window_3x3_model.py`
- Create: `software/models/gaussian_3x3_model.py`
- Create: `software/models/sobel_3x3_model.py`
- Create: `software/models/threshold_model.py`
- Create: `software/models/morphology_model.py`
- Create: `tests/test_preprocess_models.py`

**Interfaces:**
- Consumes: NumPy arrays or integer pixel/window values.
- Produces: functions named after each RTL algorithm with bit-accurate integer outputs.

- [ ] Write tests with hand-derived literals for grayscale weights, Q4.12 brightness saturation, LUT mapping, Q0.16 bilinear interpolation, line taps, zero-padded windows, Gaussian, Sobel, threshold, erosion, and dilation.
- [ ] Run `py -m unittest tests.test_preprocess_models -v` and confirm import failure because models do not yet exist.
- [ ] Implement the ten focused model files and package exports.
- [ ] Re-run the model tests and the complete Python test suite.

### Task 2: Independent Self-checking Testbenches

**Files:**
- Create: `sim/tb_rgb2gray.sv`
- Create: `sim/tb_brightness_gain.sv`
- Create: `sim/tb_gamma_lut.sv`
- Create: `sim/tb_bilinear_interp.sv`
- Create: `sim/tb_line_buffer_3x3.sv`
- Create: `sim/tb_window_3x3.sv`
- Create: `sim/tb_gaussian_3x3.sv`
- Create: `sim/tb_sobel_3x3.sv`
- Create: `sim/tb_threshold.sv`
- Create: `sim/tb_morphology.sv`

**Interfaces:**
- Consumes: one RTL module per testbench and literal expected values independently derived from the specification.
- Produces: exit-visible `TEST_PASS: <module>` or `$fatal` with `TEST_FAIL: <module>`.

- [ ] Add one independent testbench per module, including reset, valid/control alignment, normal values, boundaries, saturation or zero padding as applicable.
- [ ] Compile each testbench with `xvlog -sv` to expose syntax and interface errors.
- [ ] Elaborate each top with `xelab` and fix elaboration failures without weakening assertions.

### Task 3: Vivado Simulator PASS/FAIL Runner

**Files:**
- Create: `scripts/run_vivado_rtl_tests.ps1`
- Create: `tests/test_vivado_runner.py`

**Interfaces:**
- Consumes: Vivado `bin` from `VIVADO_HOME`/`PATH`, ten RTL/Testbench pairs.
- Produces: per-module PASS/FAIL lines, nonzero process exit on any compile/elaboration/simulation failure, and a final summary.

- [ ] Write a failing Python integration test that invokes the missing runner and expects all ten module names and a zero exit code.
- [ ] Run the test and confirm failure because the runner does not yet exist.
- [ ] Implement the runner with an isolated temporary build directory and strict output parsing.
- [ ] Run `powershell -ExecutionPolicy Bypass -File scripts/run_vivado_rtl_tests.ps1` against Vivado Simulator 2020.2.
- [ ] Fix RTL/Testbench issues using failing tests as regression cases until all ten simulations print `TEST_PASS`.
- [ ] Run the complete Python suite and archive a concise text summary under `result/rtl_sim/` only if the directory is writable.

### Task 4: Final Verification

**Files:**
- Verify: all files above plus existing `rtl/**/*.sv`.

**Interfaces:**
- Consumes: complete Python and Vivado test commands.
- Produces: evidence-backed completion status with pass/skip/fail counts.

- [ ] Run the complete Python unittest discovery.
- [ ] Run the Vivado batch runner from a clean temporary build directory.
- [ ] Confirm all ten RTL modules have one model file and one independent Testbench.
- [ ] Report any unverified limitation explicitly; do not claim PDS synthesis.

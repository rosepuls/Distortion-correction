# Distortion Coordinate Chain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a bit-accurate Brown-Conrady coordinate generator and portable RTL pipeline that produces valid bilinear source coordinates.

**Architecture:** `coordinate_gen` converts the project’s `valid/sof/eol` stream into output pixel coordinates. `distortion_core` latches per-frame Q-format camera parameters, pipelines normalization, distortion and source-coordinate conversion, then delegates floor/fraction/boundary handling to `coordinate_split`. Python produces the exact fixed-point expected results used by the RTL testbench.

**Tech Stack:** Python 3.12, NumPy, Verilog-2001/SystemVerilog-compatible RTL, Vivado XSim.

## Global Constraints

- Use the frozen `clk/rst_n/in_valid/in_sof/in_eol` stream semantics from `docs/interface_spec.md`.
- Reset is active-low and must clear every output valid/control signal.
- Latch all camera parameters only on valid `in_sof`; parameters must remain effective for the whole frame.
- Use Q13.19 for camera/source pixel coordinates, Q2.30 for inverse focal values, Q4.28 for normalized coordinates and coefficients, Q0.16 for bilinear fractions.
- Implement arithmetic right-shift truncation only; do not introduce rounding.
- `coord_valid` is true only for `0 <= x0 < IMAGE_WIDTH-1` and `0 <= y0 < IMAGE_HEIGHT-1`.
- Do not instantiate Xilinx/Pango primitives in algorithm RTL.
- The baseline must accept one input coordinate per valid clock; later range analysis may optimize width and latency.

---

### Task 1: Extend the Python Bit-accurate Coordinate Reference

**Files:**
- Modify: `software/bitaccurate_distortion.py`
- Modify: `tests/test_bitaccurate_distortion.py`

**Interfaces:**
- Consumes: `FixedPointCameraModel`, `source_coordinates_fixed`, `split_source_coordinates`.
- Produces: `source_coordinate_trace(u, v, camera) -> dict[str, int]` and existing public coordinate map APIs with unchanged behavior.

- [ ] **Step 1: Write the failing trace test**

```python
def test_trace_exposes_q_format_outputs_for_identity_mapping() -> None:
    trace = model.source_coordinate_trace(2, 1, camera)
    assert trace["src_x"] == 2 << 19
    assert trace["src_y"] == 1 << 19
    assert trace["x0"] == 2
    assert trace["y0"] == 1
    assert trace["dx"] == 0
    assert trace["dy"] == 0
```

- [ ] **Step 2: Verify the test fails because the trace API is absent**

Run: `py -m unittest tests.test_bitaccurate_distortion.BitAccurateDistortionTests.test_trace_exposes_q_format_outputs_for_identity_mapping -v`

Expected: FAIL with `AttributeError` naming `source_coordinate_trace`.

- [ ] **Step 3: Implement the trace API with the same shifts as the model**

```python
def source_coordinate_trace(u: int, v: int, camera: FixedPointCameraModel) -> dict[str, int]:
    src_x, src_y = source_coordinates_fixed([u], [v], camera)
    x0, y0, dx, dy, valid = split_source_coordinates(
        src_x.reshape(1, 1), src_y.reshape(1, 1), width=1280, height=720
    )
    return {"src_x": int(src_x[0]), "src_y": int(src_y[0]),
            "x0": int(x0[0, 0]), "y0": int(y0[0, 0]),
            "dx": int(dx[0, 0]), "dy": int(dy[0, 0]),
            "coord_valid": int(valid[0, 0])}
```

- [ ] **Step 4: Verify the model tests pass**

Run: `py -m unittest tests.test_bitaccurate_distortion -v`

Expected: PASS.

- [ ] **Step 5: Commit the isolated model change**

```bash
git add software/bitaccurate_distortion.py tests/test_bitaccurate_distortion.py
git commit -m "feat: add distortion coordinate trace model"
```

### Task 2: Create the Stream Coordinate Generator

**Files:**
- Create: `rtl/distortion/coordinate_gen.sv`
- Modify: `sim/tb_distortion_core.sv`

**Interfaces:**
- Consumes: stream controls and `IMAGE_WIDTH`.
- Produces: `out_u[12:0]`, `out_v[12:0]`, `out_valid`, `out_sof`, `out_eol` with one registered cycle of latency.

- [ ] **Step 1: Add a failing coordinate-generator section to the RTL testbench**

```verilog
send_pixel(1'b1, 1'b1, 1'b0);
expect_coordinate(13'd0, 13'd0, 1'b1, 1'b1, 1'b0);
send_pixel(1'b1, 1'b0, 1'b0);
expect_coordinate(13'd1, 13'd0, 1'b1, 1'b0, 1'b0);
```

- [ ] **Step 2: Compile it before the module exists**

Run: `xvlog -sv sim/tb_distortion_core.sv rtl/distortion/coordinate_gen.sv`

Expected: FAIL because `coordinate_gen.sv` is absent.

- [ ] **Step 3: Implement the registered coordinate stream**

```verilog
if (in_valid && in_sof) begin
    out_u <= 13'd0;
    out_v <= 13'd0;
    next_u <= 13'd1;
    next_v <= 13'd0;
end
```

Advance `next_u/next_v` only on valid input and reset them at valid `in_sof` or `in_eol`.

- [ ] **Step 4: Run the coordinate-generator testbench section**

Run: `xvlog -sv rtl/distortion/coordinate_gen.sv sim/tb_distortion_core.sv; xelab tb_distortion_core -s tb_distortion_core_sim; xsim tb_distortion_core_sim -runall`

Expected: the coordinate-generator checks pass; distortion checks may remain disabled until Task 4.

- [ ] **Step 5: Commit the coordinate generator**

```bash
git add rtl/distortion/coordinate_gen.sv sim/tb_distortion_core.sv
git commit -m "feat: add stream coordinate generator"
```

### Task 3: Create Fixed-point Arithmetic Boundary Modules

**Files:**
- Create: `rtl/distortion/normalize.sv`
- Create: `rtl/distortion/coordinate_split.sv`
- Modify: `sim/tb_distortion_core.sv`

**Interfaces:**
- `normalize` consumes signed Q13.19 `centered_x/centered_y` and signed Q2.30 inverse focal values, producing signed Q4.28 `x/y`.
- `coordinate_split` consumes signed Q13.19 `src_x/src_y`, produces signed `x0/y0`, unsigned Q0.16 `dx/dy`, and `coord_valid` based on `IMAGE_WIDTH/IMAGE_HEIGHT`.

- [ ] **Step 1: Add failing arithmetic boundary assertions**

```verilog
expect_split(-(64'sd1 <<< 17), 64'sd0, -1, 0, 16'hc000, 16'h0000, 1'b0);
expect_split((64'sd2 <<< 19), (64'sd1 <<< 19), 2, 1, 16'h0000, 16'h0000, 1'b1);
```

- [ ] **Step 2: Compile before the modules exist**

Run: `xvlog -sv sim/tb_distortion_core.sv rtl/distortion/normalize.sv rtl/distortion/coordinate_split.sv`

Expected: FAIL because the two source files are absent.

- [ ] **Step 3: Implement normalization and split logic**

```verilog
assign x_q28 = (centered_x_q19 * inv_fx_q30) >>> 21;
assign x0 = src_x_q19 >>> 19;
assign dx = src_x_q19[18:3];
assign coord_valid = (x0 >= 0) && (x0 < IMAGE_WIDTH - 1) &&
                     (y0 >= 0) && (y0 < IMAGE_HEIGHT - 1);
```

- [ ] **Step 4: Run the arithmetic boundary checks**

Run: `xvlog -sv rtl/distortion/normalize.sv rtl/distortion/coordinate_split.sv sim/tb_distortion_core.sv; xelab tb_distortion_core -s tb_distortion_core_sim; xsim tb_distortion_core_sim -runall`

Expected: all split/floor/boundary checks pass.

- [ ] **Step 5: Commit the arithmetic modules**

```bash
git add rtl/distortion/normalize.sv rtl/distortion/coordinate_split.sv sim/tb_distortion_core.sv
git commit -m "feat: add distortion fixed-point boundary modules"
```

### Task 4: Implement the Pipelined Distortion Core

**Files:**
- Create: `rtl/distortion/distortion_core.sv`
- Modify: `sim/tb_distortion_core.sv`

**Interfaces:**
- Consumes: `in_u/in_v`, stream controls and signed per-frame Q-format camera configuration.
- Produces: Q13.19 `src_x/src_y`, integer `x0/y0`, Q0.16 `dx/dy`, `coord_valid`, and delayed stream controls.
- Instantiates: `normalize` and `coordinate_split`.

- [ ] **Step 1: Add failing end-to-end checks generated from the Python model**

```verilog
send_coordinate(13'd2, 13'd1, 1'b1, 1'b1, 1'b0);
expect_distortion(64'sd1048576, 64'sd524288,
                  32'sd2, 32'sd1, 16'd0, 16'd0, 1'b1,
                  1'b1, 1'b1, 1'b0);
```

- [ ] **Step 2: Compile before the core exists**

Run: `xvlog -sv rtl/distortion/coordinate_gen.sv rtl/distortion/normalize.sv rtl/distortion/coordinate_split.sv rtl/distortion/distortion_core.sv sim/tb_distortion_core.sv`

Expected: FAIL because `distortion_core.sv` is absent.

- [ ] **Step 3: Implement the five-stage Brown-Conrady pipeline**

```verilog
// stage 1: normalized x/y
// stage 2: x2/y2/xy/r2
// stage 3: r4
// stage 4: radial and tangential terms
// stage 5: src_x/src_y, coordinate split and output register
```

Carry `fx/fy/cx/cy/k1/k2/p1/p2` alongside each transaction. At an accepted `in_sof`, select configuration input values for that transaction and update the frame-latched registers for later pixels.

- [ ] **Step 4: Run end-to-end identity, radial, tangential and boundary tests**

Run: `xvlog -sv rtl/distortion/coordinate_gen.sv rtl/distortion/normalize.sv rtl/distortion/coordinate_split.sv rtl/distortion/distortion_core.sv sim/tb_distortion_core.sv; xelab tb_distortion_core -s tb_distortion_core_sim; xsim tb_distortion_core_sim -runall`

Expected: `TEST_PASS: distortion_core`.

- [ ] **Step 5: Commit the core and testbench**

```bash
git add rtl/distortion/distortion_core.sv sim/tb_distortion_core.sv
git commit -m "feat: add pipelined distortion coordinate core"
```

### Task 5: Run Full Regression and Record the Baseline

**Files:**
- Modify: `docs/numeric_spec.md`
- Modify: `docs/interface_spec.md`

**Interfaces:**
- Consumes: implemented module latency and verified test output.
- Produces: the final `distortion_core` latency and port semantics in project specifications.

- [ ] **Step 1: Add the documented latency and output-format assertions**

```markdown
### Distortion coordinate core

`distortion_core.sv` has a fixed five-cycle valid latency from accepted input coordinate to `src_x/src_y/x0/y0/dx/dy/coord_valid` output.
```

- [ ] **Step 2: Run the entire Python distortion suite**

Run: `py -m unittest tests.test_distortion_float tests.test_bitaccurate_distortion -v`

Expected: PASS.

- [ ] **Step 3: Run the complete RTL testbench**

Run: `xvlog -sv rtl/distortion/coordinate_gen.sv rtl/distortion/normalize.sv rtl/distortion/coordinate_split.sv rtl/distortion/distortion_core.sv sim/tb_distortion_core.sv; xelab tb_distortion_core -s tb_distortion_core_sim; xsim tb_distortion_core_sim -runall`

Expected: `TEST_PASS: distortion_core` and no elaboration errors.

- [ ] **Step 4: Commit specifications and the verified baseline**

```bash
git add docs/numeric_spec.md docs/interface_spec.md
git commit -m "docs: record distortion coordinate core contract"
```

## Plan Self-Review

- Spec coverage: Tasks 1–4 implement every requested source file, fixed-point rule, stream-control rule and boundary rule; Task 5 records the verified interface/latency.
- Placeholder scan: no unresolved design values or deferred behavior are present; all test commands and interfaces are explicit.
- Type consistency: the same Q13.19/Q2.30/Q4.28/Q0.16 names and output fields are used in every task.

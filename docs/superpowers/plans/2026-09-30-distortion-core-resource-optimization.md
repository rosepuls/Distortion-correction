# Distortion Core Resource Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce the PGL50H APM use of the 1-pixel-per-clock Brown-Conrady coordinate core from 84 to no more than 40 while bounding coordinate error against the current full-precision fixed-point reference.

**Architecture:** Keep `distortion_core.sv` as the bit-accurate baseline. Add a Python candidate-format model that rescales the existing Q13.19/Q2.30/Q4.28 external configuration to narrow internal operands, uses the Horner radial form, and measures error/range on deterministic camera sweeps. Implement the accepted candidate in a separate, port-compatible optimized core, then compare it with the baseline in XSim and PDS synthesis.

**Tech Stack:** Python 3.13, NumPy, `unittest`, SystemVerilog, Vivado XSim 2020.2, PDS 2022.2-SP6.4 / PGL50H-6IFBG484.

## Global Constraints

- Preserve the `distortion_core` external ports and its SOF configuration-latch semantics.
- Keep 1 coordinate per valid clock and `valid/sof/eol` alignment.
- Keep Q13.19 `src_x/src_y`, integer floor, Q0.16 fraction, and black-border `coord_valid` semantics.
- Compare against the existing `source_coordinates_fixed` baseline; max error ≤ 1/16 pixel, mean error ≤ 1/64 pixel, and zero `coord_valid` mismatch.
- The optimized core must use ≤ 40 PGL50H APM in `Compile → Synthesize`.
- Do not run Device Map on the standalone optimized core; its analysis interface has more physical I/O than the device.
- This repository has no baseline commit; do not create commits during this work.

---

### Task 1: Create a quantized Horner Python model and candidate metrics

**Files:**
- Modify: `software/bitaccurate_distortion.py`
- Modify: `tests/test_bitaccurate_distortion.py`

**Interfaces:**
- Consumes: `FixedPointCameraModel`, `source_coordinates_fixed`, `split_source_coordinates`.
- Produces: `InternalFormat`, `CandidateMetrics`, `source_coordinates_horner_quantized`, and `evaluate_internal_format`.

- [ ] **Step 1: Write failing tests for the candidate model**

Add three tests with literal expectations:

```python
def test_quantized_horner_identity_keeps_integer_source_coordinates(self) -> None:
    camera = model.FixedPointCameraModel.from_parameters(fx=512.0, fy=512.0, cx=2.0, cy=1.0)
    candidate = model.InternalFormat.default_candidate()
    source_x, source_y = model.source_coordinates_horner_quantized([2], [1], camera, candidate)
    self.assertEqual(int(source_x[0]), 2 << 19)
    self.assertEqual(int(source_y[0]), 1 << 19)

def test_candidate_metrics_reject_coordinate_valid_mismatch(self) -> None:
    # A deliberately coarse format makes the right-edge sample cross the black-border boundary.
    camera = model.FixedPointCameraModel.from_parameters(fx=2.0, fy=2.0, cx=1.5, cy=1.0)
    coarse = model.InternalFormat(
        centered_width=6, centered_frac_bits=0,
        inverse_width=4, inverse_frac_bits=0,
        normalized_width=6, normalized_frac_bits=0,
        coefficient_width=4, coefficient_frac_bits=0,
        radius_width=6, radius_frac_bits=0,
        radial_width=6, radial_frac_bits=0,
        distorted_width=6, distorted_frac_bits=0,
        focal_width=6, focal_frac_bits=0,
    )
    metrics = model.evaluate_internal_format(4, 3, camera, coarse)
    self.assertGreater(metrics.coord_valid_mismatches, 0)

def test_horner_candidate_reports_zero_error_for_exact_zero_center(self) -> None:
    camera = model.FixedPointCameraModel.from_parameters(fx=512.0, fy=512.0, cx=2.0, cy=1.0)
    candidate = model.InternalFormat.default_candidate()
    metrics = model.evaluate_internal_format(5, 3, camera, candidate)
    self.assertEqual(metrics.coord_valid_mismatches, 0)
```

- [ ] **Step 2: Run the targeted tests and verify RED**

Run:

```powershell
py -m unittest tests.test_bitaccurate_distortion.BitAccurateDistortionTests.test_quantized_horner_identity_keeps_integer_source_coordinates -v
```

Expected: `AttributeError` because `InternalFormat` and `source_coordinates_horner_quantized` do not exist.

- [ ] **Step 3: Implement explicit candidate formats and the Horner arithmetic**

Add immutable dataclasses:

```python
@dataclass(frozen=True)
class InternalFormat:
    centered_width: int = 25
    centered_frac_bits: int = 12
    inverse_width: int = 24
    inverse_frac_bits: int = 22
    normalized_width: int = 26
    normalized_frac_bits: int = 22
    coefficient_width: int = 24
    coefficient_frac_bits: int = 20
    radius_width: int = 28
    radius_frac_bits: int = 22
    radial_width: int = 26
    radial_frac_bits: int = 22
    distorted_width: int = 26
    distorted_frac_bits: int = 22
    focal_width: int = 25
    focal_frac_bits: int = 12

    @classmethod
    def default_candidate(cls) -> "InternalFormat":
        return cls()

@dataclass(frozen=True)
class CandidateMetrics:
    max_error_pixels: float
    mean_error_pixels: float
    rmse_pixels: float
    coord_valid_mismatches: int
    ranges: dict[str, tuple[int, int]]
```

The candidate model must rescale every external configuration field explicitly, calculate `t = k1 + k2*r2` and `radial = 1 + r2*t`, rescale after every stage, and return source coordinates in Q13.19. It must never use float arithmetic inside the candidate calculation.

- [ ] **Step 4: Implement `evaluate_internal_format`**

Implement the exact signature:

```python
def evaluate_internal_format(
    width: int,
    height: int,
    camera: FixedPointCameraModel,
    internal_format: InternalFormat,
    *,
    stride: int = 1,
) -> CandidateMetrics:
```

It must sample all four corners and all raster positions selected by `stride`, compare Q13.19 source coordinates against `source_coordinates_fixed`, convert absolute raw difference by `1 << 19`, and separately compare `coord_valid` after `split_source_coordinates`.

- [ ] **Step 5: Run the complete distortion Python suite**

Run:

```powershell
py -m unittest tests.test_distortion_float tests.test_bitaccurate_distortion -v
```

Expected: all tests pass.

### Task 2: Sweep formats and select an evidence-backed hardware candidate

**Files:**
- Create: `scripts/scan_distortion_formats.py`
- Create: `result/distortion_internal_format_report.md`
- Test: `tests/test_bitaccurate_distortion.py`

**Interfaces:**
- Consumes: `InternalFormat`, `evaluate_internal_format`.
- Produces: a deterministic Markdown table of candidate error/range metrics and one `SELECTED_FORMAT` mapping.

- [ ] **Step 1: Write a failing report-contract test**

Add a test that invokes the script through `subprocess.run`, reads its Markdown output, and asserts that it contains all table headings:

```python
for heading in ("Candidate", "Max error", "Mean error", "coord_valid mismatches", "Selected"):
    self.assertIn(heading, report_text)
```

- [ ] **Step 2: Run it to verify RED**

Run:

```powershell
py -m unittest tests.test_bitaccurate_distortion.BitAccurateDistortionTests.test_format_scan_writes_candidate_table -v
```

Expected: FAIL because `scripts/scan_distortion_formats.py` is absent.

- [ ] **Step 3: Implement deterministic camera/format sweep**

The script must scan 1280×720 at stride 8 plus all border pixels for these cameras:

```python
CAMERAS = {
    "identity": dict(fx=900.0, fy=900.0, cx=639.5, cy=359.5),
    "barrel": dict(fx=900.0, fy=900.0, cx=639.5, cy=359.5, k1=-0.25, k2=0.05, p1=0.001, p2=-0.001),
    "pincushion": dict(fx=900.0, fy=900.0, cx=639.5, cy=359.5, k1=0.15, k2=0.02, p1=-0.001, p2=0.001),
}
```

Sweep these formats, in this exact order:

```python
InternalFormat(25, 12, 24, 22, 26, 22, 24, 20, 28, 22, 26, 22, 26, 22, 25, 12)
InternalFormat(25, 12, 26, 24, 28, 24, 26, 22, 30, 24, 28, 24, 28, 24, 25, 12)
InternalFormat(27, 14, 26, 24, 28, 24, 26, 22, 30, 24, 28, 24, 28, 24, 27, 14)
```

Select the narrowest candidate satisfying all specification error limits across every listed camera. If none qualifies, terminate with a nonzero status and print every failing metric.

- [ ] **Step 4: Run the format scan and inspect the report**

Run:

```powershell
py scripts/scan_distortion_formats.py --output result/distortion_internal_format_report.md
```

Expected: report contains one selected candidate with zero validity mismatches, or a nonzero exit with enough measured data to add the next wider format.

- [ ] **Step 5: Run the report-contract and model tests**

Run:

```powershell
py -m unittest tests.test_bitaccurate_distortion -v
```

Expected: all tests pass.

### Task 3: Implement the port-compatible optimized RTL core

**Files:**
- Create: `rtl/distortion/distortion_core_optimized.sv`
- Create: `sim/tb_distortion_core_optimized.sv`
- Modify: `sim/xsim_simulation_guide.md`

**Interfaces:**
- Consumes: `rtl/distortion/coordinate_split.sv`, the selected `InternalFormat` constants.
- Produces: module `distortion_core_optimized` with exactly the same ports and parameter names as `distortion_core`.

- [ ] **Step 1: Write the failing optimized-core testbench**

`tb_distortion_core_optimized.sv` must instantiate the optimized core with a 4×3 image and use literal Q values to check:

```text
identity mapping: (u,v)=(1,1) -> src=(1<<19,1<<19), x0=1,y0=1,dx=0,dy=0
right/bottom boundary -> out_coord_valid=0
one-frame configuration latch survives a mid-frame cfg change
two consecutive frames, one inserted bubble, and reset recovery preserve delayed valid/sof/eol
```

The testbench must define `CORE_LATENCY` and check each output exactly after that many valid-pipeline cycles. Initially compile it without the optimized RTL file.

- [ ] **Step 2: Verify RED**

Run:

```powershell
D:\Xilinx\Vivado\2020.2\bin\xvlog.bat -sv rtl/distortion/coordinate_split.sv sim/tb_distortion_core_optimized.sv
```

Expected: compile failure because `distortion_core_optimized` is unresolved.

- [ ] **Step 3: Implement narrowed, registered stages**

Implement these stages using only explicitly declared signed widths and arithmetic right shifts:

```text
S1: rescale centered coordinates, inverse focal and configuration to selected widths; normalize
S2: x², y², xy, r²; truncate to selected radius format
S3: Horner t = k1 + k2*r², radial = 1 + r²*t
S4: radial and tangential coordinates; truncate to selected distorted format
S5: rescaled focal conversion to Q13.19, coordinate_split and registered output
```

Latch input configuration only on `in_valid && in_sof`; clear output controls and `out_coord_valid` for bubbles and reset. Do not instantiate `normalize.sv`, because its fixed Q2.30/Q4.28 arithmetic is the baseline contract; write the selected-width normalize arithmetic locally with named signals.

- [ ] **Step 4: Generate RTL comparison vectors**

Extend `scripts/scan_distortion_formats.py` with `--vectors <path>`. It must write one line per vector:

```text
u v sof eol cfg_id src_x_q19 src_y_q19 x0 y0 dx_q16 dy_q16 coord_valid
```

Generate vectors for all corners, optical centre, both distortion cameras, and the two-frame configuration switch. The optimized testbench must consume those vectors or embed their checked literal output values.

- [ ] **Step 5: Verify XSim regression**

Run:

```powershell
D:\Xilinx\Vivado\2020.2\bin\xvlog.bat -sv rtl/distortion/coordinate_split.sv rtl/distortion/distortion_core_optimized.sv sim/tb_distortion_core_optimized.sv
D:\Xilinx\Vivado\2020.2\bin\xelab.bat tb_distortion_core_optimized -s tb_distortion_core_optimized_sim
D:\Xilinx\Vivado\2020.2\bin\xsim.bat tb_distortion_core_optimized_sim -runall
```

Expected: `TEST_PASS: distortion_core_optimized`.

### Task 4: Verify resource target and document the selected format

**Files:**
- Modify: `docs/numeric_spec.md`
- Modify: `docs/interface_spec.md`
- Modify: `pds/pgl50h_rtl_synth/rtl_1/pds_resource_timing_summary.md`
- Modify: `sim/xsim_simulation_guide.md`

**Interfaces:**
- Consumes: selected scan report, optimized XSim pass, PDS synthesized resource summary.
- Produces: numeric contract, fixed core latency, and verified PDS resource comparison.

- [ ] **Step 1: Add a failing resource-gate check**

Add a small Python test that parses `distortion_core_optimized.snr` and fails unless it finds `Total APMs` with a numeric value not greater than 40:

```python
match = re.search(r"Total APMs = ([0-9.]+) of 84", report_text)
self.assertIsNotNone(match)
self.assertLessEqual(float(match.group(1)), 40.0)
```

- [ ] **Step 2: Verify RED before the optimized PDS run**

Run:

```powershell
py -m unittest tests.test_bitaccurate_distortion.BitAccurateDistortionTests.test_optimized_pds_apm_budget -v
```

Expected: FAIL because no optimized PDS report exists.

- [ ] **Step 3: Run PDS Compile → Synthesize only**

In PDS, add `coordinate_split.sv` and `distortion_core_optimized.sv`, set `distortion_core_optimized` as top, restore:

```tcl
create_clock -name clk -period 20.000 [get_ports {clk}]
```

Run only Compile and Synthesize. Do not start Device Map because this module-level analysis top exposes more I/O than PGL50H.

- [ ] **Step 4: Run the resource-gate test**

Run:

```powershell
py -m unittest tests.test_bitaccurate_distortion.BitAccurateDistortionTests.test_optimized_pds_apm_budget -v
```

Expected: PASS only when the PDS report says `Total APMs <= 40`.

- [ ] **Step 5: Record final contracts**

Update `numeric_spec.md` with the selected internal formats, every narrowing shift, saturation behavior, and measured error metrics. Update `interface_spec.md` with the selected fixed latency. Add baseline-versus-optimized LUT/FF/APM rows and the non-Device-Map limitation to `pds_resource_timing_summary.md`.

- [ ] **Step 6: Run final regressions**

Run:

```powershell
py -m unittest discover -s tests
D:\Xilinx\Vivado\2020.2\bin\xvlog.bat -sv rtl/distortion/coordinate_split.sv rtl/distortion/distortion_core_optimized.sv sim/tb_distortion_core_optimized.sv
D:\Xilinx\Vivado\2020.2\bin\xelab.bat tb_distortion_core_optimized -s tb_distortion_core_optimized_sim
D:\Xilinx\Vivado\2020.2\bin\xsim.bat tb_distortion_core_optimized_sim -runall
```

Expected: all Python tests pass and XSim prints `TEST_PASS: distortion_core_optimized`.

## Plan Self-Review

- Spec coverage: Tasks 1–2 establish range/error evidence; Task 3 preserves the interface and throughput while implementing Horner/narrowing; Task 4 checks the ≤40 APM gate and documents the final contract.
- Placeholders: no unspecified format sweep, camera set, test command, public function, or acceptance condition remains.
- Type consistency: Task 1 defines `InternalFormat`, `CandidateMetrics`, `source_coordinates_horner_quantized`, and `evaluate_internal_format`; Tasks 2–4 use these same names.

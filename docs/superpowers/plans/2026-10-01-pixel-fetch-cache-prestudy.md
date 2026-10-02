# Pixel Fetch and Local Pixel Cache Pre-study Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a board-independent Pixel Fetch and Local Pixel Cache reference path that connects the verified distortion coordinate outputs to bilinear interpolation and quantitatively evaluates DDR access cost.

**Architecture:** The existing `distortion_core.sv` produces Q13.19 source coordinates and `coordinate_split.sv` produces integer neighbors, Q0.16 fractions, and `coord_valid`. A Python address-trace model will convert these coordinates into logical pixel requests, while a cache model will compare no-cache, row-window, and tile-cache policies. A variable-latency SystemVerilog memory model will then verify the request/response protocol and the functional path into the existing `bilinear_interp.sv` without requiring a camera, development board, DDR3 PHY, or vendor IP.

**Tech Stack:** Python 3.12/3.13, NumPy, `unittest`, SystemVerilog, Vivado XSim, and PDS 2022.2 for optional device-level synthesis of portable RTL.

## Global Constraints

- Preserve the logical address rule `addr = y * FRAME_STRIDE_PIXELS + x`; do not convert to DDR byte addresses in the algorithm or model layer.
- RGB source pixels use RGB888 and logical pixel size is 3 bytes; physical DDR packing remains a later board-layer concern.
- A source coordinate is fetchable only when `0 <= x0 < width-1` and `0 <= y0 < height-1`.
- When `coord_valid=0`, issue no memory request and output black RGB with the correct delayed stream controls.
- Requests are accepted only on `req_valid && req_ready`; responses are accepted only on `rsp_valid && rsp_ready`.
- The first behavior model returns responses in request acceptance order; no hidden out-of-order behavior is allowed.
- The existing `valid/sof/eol` semantics remain unchanged, and all controls travel with their associated output pixel.
- Do not instantiate Xilinx or Pango primitives in the algorithm, cache model, or behavior-level fetch RTL.
- No camera or development board is required; all functional tests use generated checkerboards, grids, ramps, and deterministic RGB patterns.
- This repository currently has no baseline commit; do not create commits as part of this plan unless the user explicitly requests them.

## Current Baseline

The following components are already present and verified by the user:

```text
rtl/distortion/coordinate_gen.sv
rtl/distortion/normalize.sv
rtl/distortion/distortion_core.sv
rtl/distortion/coordinate_split.sv
rtl/interpolation/bilinear_interp.sv
software/bitaccurate_distortion.py
sim/tb_distortion_core.sv
sim/tb_distortion_stream.sv
```

The next missing deliverables are the address trace, cache policy comparison, memory request/response behavior model, and a functional fetch-to-bilinear integration test.

---

### Task 1: Create the logical bilinear address-trace model

**Files:**
- Create: `software/address_trace_model.py`
- Create: `tests/test_address_trace_model.py`

**Interfaces:**
- Consumes: equal-shaped integer arrays `x0`, `y0`, `coord_valid`; image width, height, and optional `frame_stride_pixels`.
- Produces: `BilinearAddressRequest`, `AddressTraceMetrics`, and `generate_address_trace(...)`.

Define these public types and functions:

```python
@dataclass(frozen=True)
class BilinearAddressRequest:
    output_index: int
    x0: int
    y0: int
    addresses: tuple[int, int, int, int]

@dataclass(frozen=True)
class AddressTraceMetrics:
    total_outputs: int
    valid_outputs: int
    invalid_outputs: int
    total_source_reads: int
    unique_source_addresses: int
    repeated_source_reads: int
    cross_row_pairs: int
    logical_bytes_read: int
    average_consecutive_run: float
    maximum_consecutive_run: int

def logical_pixel_address(x: int, y: int, frame_stride_pixels: int) -> int:
    ...

def generate_address_trace(
    x0: ArrayLike,
    y0: ArrayLike,
    coord_valid: ArrayLike,
    width: int,
    height: int,
    *,
    frame_stride_pixels: int | None = None,
) -> tuple[list[BilinearAddressRequest], AddressTraceMetrics]:
    ...
```

- [x] **Step 1: Write the failing address and boundary tests**

```python
def test_logical_address_uses_pixels_not_rgb_bytes(self) -> None:
    self.assertEqual(logical_pixel_address(3, 2, 8), 19)

def test_valid_request_contains_four_row_major_neighbors(self) -> None:
    requests, metrics = generate_address_trace(
        np.array([[1]]), np.array([[1]]), np.array([[True]]), 4, 4
    )
    self.assertEqual(requests[0].addresses, (5, 6, 9, 10))
    self.assertEqual(metrics.total_source_reads, 4)

def test_invalid_coordinate_generates_no_memory_request(self) -> None:
    requests, metrics = generate_address_trace(
        np.array([[3]]), np.array([[1]]), np.array([[False]]), 4, 4
    )
    self.assertEqual(requests, [])
    self.assertEqual(metrics.invalid_outputs, 1)
```

- [x] **Step 2: Run the targeted tests and verify RED**

Run:

```powershell
py -m unittest tests.test_address_trace_model -v
```

Expected: FAIL because `software/address_trace_model.py` does not exist.

- [x] **Step 3: Implement logical request generation**

For each flattened output coordinate, emit a request only when `coord_valid` is true and all four neighbors are in range:

```python
p00 = y0 * stride + x0
p10 = y0 * stride + x0 + 1
p01 = (y0 + 1) * stride + x0
p11 = (y0 + 1) * stride + x0 + 1
```

Use `frame_stride_pixels=width` by default. Count logical RGB bytes as `total_source_reads * 3`; do not multiply addresses by 3.

- [x] **Step 4: Add repeated-access and sequential-run metrics**

For the flattened request sequence, count unique addresses, repeated reads, adjacent address pairs, row transitions, and consecutive runs. Metrics must be deterministic for the same arrays.

- [x] **Step 5: Run the complete address-trace tests**

Verification: the focused address-trace and existing distortion/preprocess model suite passes (24 tests). The sandboxed repository-wide run hit two Windows permission errors in existing format-scan temp-directory tests, while the same 45-test run with host filesystem permissions passed; the errors do not involve the new address-trace model.

Run:

```powershell
py -m unittest tests.test_address_trace_model -v
```

Expected: all tests pass, including 4×4 corner invalidation, a 5×5 interior request, custom frame stride, and a repeated-address trace.

---

### Task 2: Compare cache policies in Python

**Files:**
- Create: `software/cache_model.py`
- Create: `tests/test_cache_model.py`
- Create: `scripts/evaluate_pixel_fetch_cache.py`
- Create: `docs/reports/pixel_fetch_cache_summary.md`

**Interfaces:**
- Consumes: `BilinearAddressRequest` objects from `address_trace_model.py`.
- Produces: `CacheConfig`, `CacheMetrics`, `simulate_cache(...)`, and a deterministic Markdown report.

Define these public types and functions:

```python
@dataclass(frozen=True)
class CacheConfig:
    name: str
    tile_width: int
    tile_height: int
    burst_length: int

@dataclass(frozen=True)
class CacheMetrics:
    policy: str
    output_requests: int
    source_pixel_requests: int
    cache_hits: int
    cache_misses: int
    cache_hit_rate: float
    ddr_read_pixels: int
    ddr_read_bytes: int
    ddr_bursts: int
    average_burst_length: float
    cache_capacity_pixels: int

def simulate_cache(
    requests: Sequence[BilinearAddressRequest],
    width: int,
    height: int,
    config: CacheConfig,
) -> CacheMetrics:
    ...
```

Implement three deterministic policies:

```python
NO_CACHE = CacheConfig("no_cache", 1, 1, 1)
ROW_WINDOW = CacheConfig("row_window", 4, 2, 4)
TILE_16X4 = CacheConfig("tile_16x4", 16, 4, 16)
```

`no_cache` counts every requested source pixel as one DDR read. Row and tile policies load aligned regions on a miss, split each row into bursts of at most `burst_length`, and retain only the configured region. Invalid outputs never enter the simulator.

- [x] **Step 1: Write cache metric tests**

```python
def test_tile_cache_reuses_repeated_neighbor_pixels(self) -> None:
    requests, _ = generate_address_trace(
        np.array([[1, 1]]), np.array([[1, 1]]), np.array([[True, True]]), 8, 8
    )
    no_cache = simulate_cache(requests, 8, 8, NO_CACHE)
    tile = simulate_cache(requests, 8, 8, TILE_16X4)
    self.assertLess(tile.ddr_read_pixels, no_cache.ddr_read_pixels)
    self.assertGreater(tile.cache_hit_rate, 0.0)

def test_cache_metrics_are_deterministic(self) -> None:
    self.assertEqual(simulate_cache(REQUESTS, 8, 8, TILE_16X4),
                     simulate_cache(REQUESTS, 8, 8, TILE_16X4))
```

- [x] **Step 2: Run the cache tests and verify RED**

Run:

```powershell
py -m unittest tests.test_cache_model -v
```

Expected: FAIL because `software/cache_model.py` does not exist.

- [x] **Step 3: Implement no-cache, row-window, and tile-cache simulation**

Use logical pixel coordinates and aligned tile keys. A cache miss must account for every in-bounds pixel loaded into the tile and for the row-burst count. Keep `cache_capacity_pixels` explicit in the returned metrics so the report can compare the design against available DRM/RAM capacity.

- [x] **Step 4: Generate deterministic 720P traces**

The script must create these synthetic source-coordinate cases without any camera or board:

```text
identity grid: source_x=u, source_y=v
barrel: k1=-0.25, k2=0.05, p1=0.001, p2=-0.001
pincushion: k1=0.15, k2=0.02, p1=-0.001, p2=0.001
```

Use the existing `software/bitaccurate_distortion.py` map and `split_source_coordinates` for `x0/y0/coord_valid`. Evaluate 1280×720 with raster stride 8 plus every border coordinate.

- [x] **Step 5: Write and inspect the cache report**

Run:

```powershell
py scripts/evaluate_pixel_fetch_cache.py --output docs/reports/pixel_fetch_cache_summary.md
```

The report must contain one row per camera and policy with `cache_hit_rate`, `ddr_read_bytes`, `ddr_bursts`, `average_burst_length`, and `cache_capacity_pixels`. It must explicitly state that the bandwidth result is a model estimate, not a board measurement.

- [x] **Step 6: Run model regression**

Run:

```powershell
py -m unittest tests.test_address_trace_model tests.test_cache_model tests.test_bitaccurate_distortion -v
```

Expected: all tests pass and the report contains the three policies for all three synthetic cameras.

Verification: the address-trace, cache, and non-Icarus distortion/preprocess model tests pass. The sandboxed run hit the existing format-scan temp-directory permission restriction; the full 45-test run with host filesystem permissions passed.

---

### Task 3: Freeze the request/response contract and create the DDR behavior model

**Files:**
- Modify: `docs/interface_spec.md`
- Create: `rtl/memory/pixel_fetch_if.sv`
- Create: `sim/models/ddr_behavior_model.sv`
- Create: `sim/tb_ddr_behavior_model.sv`

**Interfaces:**
- Request channel: `req_valid`, `req_ready`, `req_addr`.
- Response channel: `rsp_valid`, `rsp_ready`, `rsp_data`.
- Logical `req_addr` is a pixel number; `rsp_data` is RGB888.

Add this exact contract to `docs/interface_spec.md`:

```text
req_addr = y * FRAME_STRIDE_PIXELS + x
request_accept = req_valid && req_ready
response_accept = rsp_valid && rsp_ready
response order = request acceptance order
```

`rtl/memory/pixel_fetch_if.sv` shall contain a plain-port, vendor-neutral signal declaration module named `pixel_fetch_if` with parameters `ADDR_WIDTH=32` and `PIXEL_WIDTH=24`; it must not contain DDR protocol logic or vendor primitives. The behavior model is the endpoint used by simulation.

The behavior model shall expose:

```text
parameter integer MEMORY_WORDS = 1024
parameter integer FIXED_LATENCY = 2
parameter integer MAX_LATENCY = 2
parameter string INIT_FILE = ""
```

It shall accept one request when idle, delay it by `FIXED_LATENCY` cycles, optionally insert deterministic latency from 1 through `MAX_LATENCY` when `MAX_LATENCY > FIXED_LATENCY`, and hold `rsp_valid/rsp_data` until `rsp_ready` is asserted.

- [x] **Step 1: Add protocol assertions to the testbench**

Check that a request is accepted only on `req_valid && req_ready`, a response remains stable while stalled, and two accepted requests return in order.

- [x] **Step 2: Compile the testbench before the model exists**

Run:

```powershell
xvlog -sv rtl/memory/pixel_fetch_if.sv sim/tb_ddr_behavior_model.sv
```

Expected: FAIL because the behavior model is absent.

- [x] **Step 3: Implement the model with explicit response holding**

Use an initialized RGB888 memory array and a one-entry pending request register. Do not drop requests, change response data while `rsp_valid && !rsp_ready`, or accept a second request until the configured model can represent it.

- [x] **Step 4: Add fixed-latency, variable-latency, and backpressure tests**

The testbench must cover:

```text
one request with FIXED_LATENCY=2
two requests with response backpressure
three requests with deterministic latency 1..MAX_LATENCY
reset while a response is pending
```

- [x] **Step 5: Run the protocol simulation**

Run:

```powershell
xvlog -sv rtl/memory/pixel_fetch_if.sv sim/models/ddr_behavior_model.sv sim/tb_ddr_behavior_model.sv
xelab tb_ddr_behavior_model -s tb_ddr_behavior_model_sim
xsim tb_ddr_behavior_model_sim -runall
```

Expected: `TEST_PASS: ddr_behavior_model` and no response-order or response-stability failures.

Verification: Vivado 2020.2 `xvlog`/`xelab`/`xsim` completed successfully and printed `TEST_PASS: ddr_behavior_model`. The compile-only RED command did not reject the unresolved testbench module until elaboration, so the actual gate was the successful elaboration and protocol simulation.

---

### Task 4: Implement functional Pixel Fetch to Bilinear integration

**Files:**
- Create: `rtl/memory/pixel_fetch_engine.sv`
- Create: `sim/tb_pixel_fetch_bilinear.sv`
- Modify: `sim/xsim_simulation_guide.md`

**Interfaces:**
- Input coordinate stream: `in_x0`, `in_y0`, `in_dx_q16`, `in_dy_q16`, `in_coord_valid`, `in_valid`, `in_sof`, `in_eol`.
- Memory request/response: the Task 3 logical pixel protocol.
- Output stream: RGB888 `out_pixel`, `out_valid`, `out_sof`, `out_eol`.

The first functional engine may process one coordinate transaction at a time, but it must not lose an input coordinate accepted by its explicit `in_ready` signal. For a valid coordinate it requests the four addresses in the fixed order `P00`, `P10`, `P01`, `P11`, waits for four ordered RGB888 responses, and feeds them to the existing `bilinear_interp.sv`. For an invalid coordinate it emits black without a request.

- [x] **Step 1: Write the failing integration test**

Use a 4×4 RGB image whose pixel value is derived from its logical address:

```text
R = addr[7:0]
G = addr[7:0] + 8'h10
B = addr[7:0] + 8'h20
```

Send an interior coordinate `(x0,y0)=(1,1)` with `dx=0.5`, `dy=0.5`, then send a right-edge invalid coordinate. Check four request addresses, one interpolated RGB result, no request for the invalid coordinate, and aligned `sof/eol`.

- [x] **Step 2: Compile the testbench before the engine exists**

Run:

```powershell
xvlog -sv rtl/interpolation/bilinear_interp.sv rtl/memory/pixel_fetch_if.sv rtl/memory/pixel_fetch_engine.sv sim/models/ddr_behavior_model.sv sim/tb_pixel_fetch_bilinear.sv
```

Expected: FAIL because `pixel_fetch_engine.sv` is absent.

- [x] **Step 3: Implement the request FSM**

Use these states:

```text
IDLE → REQUEST_P00 → WAIT_P00 → REQUEST_P10 → WAIT_P10
     → REQUEST_P01 → WAIT_P01 → REQUEST_P11 → WAIT_P11
     → BILINEAR_OUTPUT → IDLE
```

Only advance a request state on `req_valid && req_ready`; only capture a response on `rsp_valid && rsp_ready`. Keep the input control metadata in registers until the bilinear output is emitted.

- [x] **Step 4: Add bubbles, reset, and response-stall tests**

Cover an input bubble between coordinates, delayed responses, a stalled response, a reset before the fourth response, two consecutive frames with different RGB data, and invalid coordinates at the final row/column.

- [x] **Step 5: Run the functional integration simulation**

Run:

```powershell
xvlog -sv rtl/interpolation/bilinear_interp.sv rtl/memory/pixel_fetch_if.sv rtl/memory/pixel_fetch_engine.sv sim/models/ddr_behavior_model.sv sim/tb_pixel_fetch_bilinear.sv
xelab tb_pixel_fetch_bilinear -s tb_pixel_fetch_bilinear_sim
xsim tb_pixel_fetch_bilinear_sim -runall
```

Expected: `TEST_PASS: pixel_fetch_bilinear`, correct four-address order, correct RGB interpolation, and no invalid-coordinate memory request.

Verification: Vivado 2020.2 `xvlog`/`xelab`/`xsim` completed successfully and printed `TEST_PASS: pixel_fetch_bilinear`. The test covers request order, two RGB patterns across frame starts, right/bottom invalid coordinates, and reset while the final response is pending. Response holding itself is covered by the Task 3 DDR model test; the engine keeps `rsp_ready` asserted whenever it is waiting for a response.

---

### Task 5: Close the no-board architecture loop

**Files:**
- Modify: `docs/numeric_spec.md`
- Modify: `docs/interface_spec.md`
- Modify: `docs/reports/pixel_fetch_cache_summary.md`
- Modify: `sim/xsim_simulation_guide.md`

**Interfaces:**
- Consumes: passing Python trace/cache models, passing behavior model, passing fetch/bilinear simulation.
- Produces: a reproducible no-board Pixel Fetch architecture baseline and an explicit list of board-dependent unknowns.

- [x] **Step 1: Record the logical address and invalid-border contract**

Document that invalid coordinates produce black output and no memory request, while logical addresses remain independent of RGB byte packing and DDR controller addressing.

- [x] **Step 2: Record the selected cache candidate and model limits**

Copy the selected policy metrics into the report and label them as model estimates. Record the candidate tile dimensions, burst length, cache capacity, expected read bytes/frame, and estimated bandwidth.

- [x] **Step 3: Record the functional latency and throughput limitation**

Document the measured request/response latency and the first engine's one-transaction-at-a-time limitation. State that final 720P60 throughput requires prefetch, buffering, or a cache scheduler and cannot be claimed from the behavior model alone.

- [x] **Step 4: Run the complete no-board regression**

Run:

```powershell
py -m unittest discover -s tests -v
xvlog -sv rtl/interpolation/bilinear_interp.sv rtl/memory/pixel_fetch_if.sv rtl/memory/pixel_fetch_engine.sv sim/models/ddr_behavior_model.sv sim/tb_pixel_fetch_bilinear.sv
xelab tb_pixel_fetch_bilinear -s tb_pixel_fetch_bilinear_sim
xsim tb_pixel_fetch_bilinear_sim -runall
```

Expected: all Python tests pass, the integration simulation prints `TEST_PASS: pixel_fetch_bilinear`, and the report distinguishes measured simulation behavior from future board measurements.

Verification: the full Python regression passed with 45 tests and 4 expected skips for missing Icarus Verilog, and both Vivado protocol/integration simulations passed. The first RTL-level PDS synthesis check remains optional and deferred because the existing PDS project top is `distortion_core_optimized`, not the new one-transaction Pixel Fetch engine.

- [ ] **Step 5: Optional PDS compile/synthesis check**

Add only portable RTL to the PDS project:

```text
pixel_fetch_if.sv
pixel_fetch_engine.sv
bilinear_interp.sv
```

Run Compile → Synthesize with the existing device-level clock constraint. Record LUT6, FF, DRM, APM, critical path, and warnings. Do not add DDR3 PHY, HDMI pins, PLL IP, or guessed board constraints.

## Plan Self-Review

- Spec coverage: Tasks 1–2 quantify logical addresses, repeated reads, cache hits, bursts, and model bandwidth; Tasks 3–4 define and verify the variable-latency protocol and functional bilinear path; Task 5 records the no-board limitations and PDS boundary.
- Placeholder scan: no unresolved design values are used; cache policies, function signatures, test data, commands, and acceptance conditions are explicit.
- Type consistency: `BilinearAddressRequest` and `AddressTraceMetrics` flow from Task 1 into `CacheMetrics` in Task 2; Task 3 uses logical addresses from Task 1; Task 4 uses the same request/response signal names and RGB888 ordering.

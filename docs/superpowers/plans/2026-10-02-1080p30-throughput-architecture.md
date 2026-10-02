# 1080P30 Throughput Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task with review checkpoints.

**Goal:** Replace the current four-single-pixel DDR read path with a measurable 1080P30 RGBX8888 burst and Tile Cache pipeline that can sustain the complete 1920×1080 raster at a 100 MHz algorithm clock.

**Architecture:** The work is split into three independently testable layers. First, the software model becomes a full-raster physical DDR traffic model. Second, vendor-neutral RTL implements a 512-entry coordinate FIFO boundary, a 32×4 four-way Tile Cache, and a four-bank 2×2 neighborhood path. Third, the PGL50H board wrapper adopts RGBX8888 Ping-Pong frame buffers and 1080P30 video timing. The legacy single-pixel path remains available for functional regression until the cached path passes image and throughput tests.

**Tech Stack:** Python 3, `unittest`, NumPy, SystemVerilog, existing DDR behavior model, PDS-generated DDR3/PLL IP, MES50HP vendor RTL, PowerShell simulation runners.

## Global Constraints

- Formal target is `1920×1080 @ 30 fps`; 1080P60 is out of scope for this milestone.
- Algorithm and DDR user logic target is 100 MHz; frame budget is 3,333,333 cycles and average budget is 1.607 cycles/pixel.
- Real-time frame storage format is RGBX8888; one DDR data beat is 256 bit and contains eight pixels.
- First Tile Cache configuration is 32×4 pixels, 128 resident Tiles, 32 sets × 4 ways, four data banks, and four 256-bit beats per Tile row.
- Invalid source coordinates produce black output without a DDR request.
- The official DDR3/HDMI vendor files are integration dependencies and are not reformatted.
- Generated PDS compile, place-route, timing, and bitstream directories remain ignored by Git.
- Every new Python behavior follows red-green-refactor; every new RTL block has a focused SystemVerilog testbench before integration.
- Existing image-level and board-structure regressions must remain runnable during migration.

---

### Task 1: Establish the 1080P30 full-raster traffic model

**Files:**
- Modify: `software/cache_model.py`
- Modify: `scripts/evaluate_pixel_fetch_cache.py`
- Modify: `tests/test_cache_model.py`
- Create: `tests/test_throughput_model.py`
- Create: `docs/reports/pixel_fetch_cache_1080p30.md`

**Interfaces:**
- `CacheConfig` gains `set_count`, `ways`, `pixel_bytes`, and `burst_beats` while retaining compatibility with `NO_CACHE` for existing tests.
- `simulate_cache(requests, width, height, config)` returns `CacheMetrics` with `cache_hits`, `cache_misses`, `ddr_read_bytes`, `ddr_bursts`, `average_burst_length`, and `cache_capacity_pixels`.
- `build_report(width=1920, height=1080, fps=30, full_raster=True)` evaluates identity, barrel, and pincushion cameras without stride extrapolation.

- [ ] **Step 1: Add failing tests for physical full-raster behavior.**

```python
def test_tile_cache_uses_rgbx8888_and_four_beat_row_bursts(self):
    config = CacheConfig(
        "tile_32x4_128_4way",
        tile_width=32,
        tile_height=4,
        burst_length=8,
        set_count=32,
        ways=4,
        pixel_bytes=4,
        burst_beats=1,
    )
    metrics = simulate_cache(self.requests, 64, 8, config)
    self.assertEqual(metrics.ddr_bursts % 4, 0)
    self.assertGreater(metrics.ddr_read_bytes, 0)
```

- [ ] **Step 2: Run the focused tests and confirm the new API fails for the expected reason.**

Run:

```powershell
python -m unittest tests.test_cache_model tests.test_throughput_model -v
```

Expected: the new configuration fields or full-raster report behavior are missing; existing legacy tests must continue to run.

- [ ] **Step 3: Implement set-associative Tile accounting.**

Use `(tile_y * tiles_per_row + tile_x) % set_count` as the deterministic set index, store up to `ways` tags per set, and count a miss once per aligned Tile rather than once per neighbor. A 32×4 RGBX8888 Tile loads four row bursts of eight pixels per burst, so its physical load is `32 * 4 * 4 = 512` bytes and 16 256-bit beats.

- [ ] **Step 4: Replace sparse report generation with complete 1920×1080 raster evaluation.**

Use all coordinates from `np.indices((height, width))`, retain the existing fixed-point camera model, and report per-frame bytes, bytes per second at 30 fps, cache hit rate, burst count, and estimated total traffic for input write + source read + output write + display read.

- [ ] **Step 5: Run the focused and existing Python tests.**

Run:

```powershell
python -m unittest discover -s tests -p "test_*.py" -v
python scripts/evaluate_pixel_fetch_cache.py --output docs/reports/pixel_fetch_cache_1080p30.md
```

Expected: all tests pass, the report contains exactly 1920×1080 output coordinates, and the 32×4/128-entry candidate reports source traffic below the 10 MB/frame design threshold for the representative camera models.

- [ ] **Step 6: Commit the model milestone.**

```powershell
git add software/cache_model.py scripts/evaluate_pixel_fetch_cache.py tests/test_cache_model.py tests/test_throughput_model.py docs/reports/pixel_fetch_cache_1080p30.md
git commit -m "test: establish full raster 1080p30 traffic baseline"
```

### Task 2: Add the RGBX8888 DDR address and burst model

**Files:**
- Create: `software/ddr_traffic_model.py`
- Create: `tests/test_ddr_traffic_model.py`
- Modify: `software/address_trace_model.py`

**Interfaces:**
- `rgbx_pixel_byte_address(x, y, width, frame_base_byte=0) -> int` returns `frame_base_byte + ((y * width + x) * 4)`.
- `tile_row_bursts(tile_x, tile_y, width, height, frame_base_byte=0) -> tuple[tuple[int, int], ...]` returns aligned `(byte_address, beat_count)` pairs for the four valid Tile rows.
- `TrafficTotals` reports input bytes, source bytes, output bytes, display bytes, total bytes, and bytes per second.

- [ ] **Step 1: Write failing address-alignment tests.**

```python
def test_eight_rgbx_pixels_fit_one_256_bit_beat(self):
    self.assertEqual(rgbx_pixel_byte_address(8, 0, 1920), 32)

def test_tile_row_is_four_aligned_beats(self):
    bursts = tile_row_bursts(1, 2, 1920, 1080)
    self.assertEqual(len(bursts), 4)
    self.assertTrue(all(beats == 4 for _address, beats in bursts))
```

- [ ] **Step 2: Run the tests and verify they fail because the module is absent.**

```powershell
python -m unittest tests.test_ddr_traffic_model -v
```

- [ ] **Step 3: Implement address and burst calculations.**

Reject negative coordinates and dimensions that are not positive. Align each row burst to the 32-byte RGBX beat boundary. At the right and bottom image borders, reduce the final burst count to the number of in-bounds beats while preserving the four-neighbor invalid-coordinate rule.

- [ ] **Step 4: Add total-bandwidth calculations and boundary tests.**

Cover `x=0`, `x=width-1`, `y=0`, `y=height-1`, a Tile crossing the right edge, and the 1920×1080 frame totals. The 1080P30 four-frame-stream baseline must equal `1920 * 1080 * 4 * 30 * 4 = 995,328,000` bytes per second before cache-fill overhead.

- [ ] **Step 5: Run all Python tests and commit.**

```powershell
python -m unittest discover -s tests -p "test_*.py" -v
git add software/ddr_traffic_model.py tests/test_ddr_traffic_model.py software/address_trace_model.py
git commit -m "feat: model RGBX8888 DDR burst traffic"
```

### Task 3: Implement the coordinate FIFO boundary

**Files:**
- Create: `rtl/memory/coordinate_fifo.sv`
- Create: `sim/tb_coordinate_fifo.sv`
- Create: `sim/run_coordinate_fifo.ps1`

**Interfaces:**
- Input: `in_valid`, `in_ready`, `in_x0`, `in_y0`, `in_fx`, `in_fy`, `in_coord_valid`, `in_sof`, `in_eol`.
- Output: matching `out_valid`, `out_ready`, and the same payload fields.
- Parameters: `DEPTH=512`, `COORD_WIDTH=12`, `FRAC_WIDTH=16`.

- [ ] **Step 1: Write the failing SystemVerilog testbench.**

The testbench shall push 513 tagged coordinates, hold `out_ready` low for 17 cycles, verify FIFO backpressure at depth 512, then drain and compare every payload and marker in order.

- [ ] **Step 2: Run the testbench and confirm the module is missing.**

```powershell
powershell -ExecutionPolicy Bypass -File sim/run_coordinate_fifo.ps1
```

- [ ] **Step 3: Implement the synchronous FIFO.**

Use binary read/write pointers, a count or extra-MSB full/empty scheme, registered payload storage, and simultaneous read/write support. `in_ready` must remain asserted on a same-cycle dequeue when the FIFO is full.

- [ ] **Step 4: Run the FIFO testbench and preserve the failing-case regression.**

Expected: zero mismatches, full and empty flags never overlap, and the 513th item is accepted only after the first dequeue.

- [ ] **Step 5: Commit the FIFO milestone.**

```powershell
git add rtl/memory/coordinate_fifo.sv sim/tb_coordinate_fifo.sv sim/run_coordinate_fifo.ps1
git commit -m "feat: add coordinate FIFO for streaming fetch"
```

### Task 4: Implement the DDR burst reader

**Files:**
- Create: `rtl/memory/ddr_burst_reader.sv`
- Create: `sim/tb_ddr_burst_reader.sv`
- Create: `sim/run_ddr_burst_reader.ps1`

**Interfaces:**
- Fill request: `fill_req_valid`, `fill_req_ready`, `fill_tile_x`, `fill_tile_y`, `fill_row_index`.
- DDR command: `rd_cmd_en`, `rd_cmd_ready`, `rd_cmd_addr`, `rd_cmd_len`.
- DDR data: `rd_data_valid`, `rd_data_ready`, `rd_data[255:0]`, `rd_data_last`.
- Cache write stream: `fill_data_valid`, `fill_data_ready`, `fill_data[255:0]`, `fill_tile_x`, `fill_tile_y`, `fill_row_index`, `fill_beat_index`.

- [ ] **Step 1: Write tests for one Tile row, four beats, and backpressure.**

The testbench must return four known 256-bit beats in reverse timing conditions, hold `fill_data_ready` low for 5 cycles, and prove the reader never drops or reorders beats.

- [ ] **Step 2: Verify the test fails because the reader is absent.**

```powershell
powershell -ExecutionPolicy Bypass -File sim/run_ddr_burst_reader.ps1
```

- [ ] **Step 3: Implement the command/data FSM.**

Issue `rd_cmd_len=4` for a full Tile row, wait for command acceptance, accept exactly four data beats, and emit `fill_beat_index=0..3`. Do not issue the next row until the previous row is complete in the initial implementation.

- [ ] **Step 4: Run the burst reader tests with zero, one, and variable response latency.**

Expected: four commands per Tile, 16 data beats per Tile, no output while reset is asserted, and no response loss under backpressure.

- [ ] **Step 5: Commit the reader milestone.**

```powershell
git add rtl/memory/ddr_burst_reader.sv sim/tb_ddr_burst_reader.sv sim/run_ddr_burst_reader.ps1
git commit -m "feat: add four-beat DDR Tile burst reader"
```

### Task 5: Implement the four-way, four-bank Tile Cache

**Files:**
- Create: `rtl/memory/pixel_tile_cache.sv`
- Create: `sim/tb_pixel_tile_cache.sv`
- Create: `sim/run_pixel_tile_cache.ps1`
- Modify: `rtl/memory/pixel_fetch_if.sv`

**Interfaces:**
- Lookup request: `lookup_valid`, `lookup_ready`, `lookup_x0`, `lookup_y0`.
- Lookup response: `lookup_rsp_valid`, `lookup_rsp_ready`, four `pixel_*[31:0]`, `cache_hit`, `coord_valid`.
- Fill request: `fill_req_valid`, `fill_req_ready`, `fill_tile_x`, `fill_tile_y`, `fill_row_index`.
- Fill data: `fill_data_valid`, `fill_data_ready`, `fill_data[255:0]`, `fill_row_index`, `fill_beat_index`.
- Parameters: `IMAGE_WIDTH=1920`, `IMAGE_HEIGHT=1080`, `TILE_W=32`, `TILE_H=4`, `SET_COUNT=32`, `WAYS=4`.

- [ ] **Step 1: Write failing hit, miss, replacement, and four-bank tests.**

The testbench shall fill a known Tile, query an interior coordinate, query a 2×2 neighborhood crossing an x boundary, fill five tags mapping to one set, and verify pseudo-LRU replacement does not evict the most recently used tag.

- [ ] **Step 2: Run the cache testbench and confirm the implementation is absent.**

```powershell
powershell -ExecutionPolicy Bypass -File sim/run_pixel_tile_cache.ps1
```

- [ ] **Step 3: Implement Tag arrays and replacement state.**

Compute `tile_x=x0[11:5]`, `tile_y=y0[11:2]`, set index `(tile_y * 60 + tile_x) % 32`, and compare all four ways in parallel. A query that touches multiple Tiles must report all required Tags before asserting `lookup_rsp_valid`.

- [ ] **Step 4: Implement four parity banks and line unpacking.**

Unpack each 256-bit beat into eight RGBX8888 words, place each word in bank `{source_y[0], source_x[0]}`, and address the bank with the Tile-local coordinates. Return the four neighboring words in `P00/P10/P01/P11` order.

- [ ] **Step 5: Run directed and randomized cache tests.**

Expected: a hit returns all four correct pixels in one response handshake; a miss produces exactly the required fill request; invalid coordinates never request a fill; replacement results are deterministic.

- [ ] **Step 6: Commit the cache milestone.**

```powershell
git add rtl/memory/pixel_tile_cache.sv rtl/memory/pixel_fetch_if.sv sim/tb_pixel_tile_cache.sv sim/run_pixel_tile_cache.ps1
git commit -m "feat: add four-bank RGBX Tile Cache"
```

### Task 6: Integrate cached Pixel Fetch with the existing bilinear path

**Files:**
- Create: `rtl/memory/cached_pixel_fetch_engine.sv`
- Modify: `rtl/interpolation/bilinear_interp.sv`
- Modify: `rtl/distortion/distortion_image_pipeline.sv`
- Modify: `rtl/board/mes50hp/mes50hp_top.sv`
- Create: `sim/tb_cached_pixel_fetch_engine.sv`
- Create: `sim/run_cached_pixel_fetch_engine.ps1`

**Interfaces:**
- Coordinate input is the Task 3 FIFO payload.
- Cache fill command/data is the Task 4/5 interface.
- Bilinear output remains RGB888 with `out_valid`, `out_ready`, `out_sof`, and `out_eol`.
- Add parameter `USE_TILE_CACHE=1`; `USE_TILE_CACHE=0` preserves the current logical single-pixel path for legacy tests.

- [ ] **Step 1: Add an image-level failing test for the cached path.**

Use a small 64×32 RGBX frame, deterministic 2×2 source neighborhoods, and a DDR model with 3–11 cycle variable latency. Compare every output RGB888 pixel and frame marker against the existing Python golden frame.

- [ ] **Step 2: Run the test before implementation.**

```powershell
powershell -ExecutionPolicy Bypass -File sim/run_cached_pixel_fetch_engine.ps1
```

Expected: the cached path is not yet selected or the new engine is missing; the legacy path remains green.

- [ ] **Step 3: Implement the cached fetch FSM.**

Accept coordinates while the FIFO is not full, query the Cache, request missing Tile rows through `ddr_burst_reader`, wait until all required Tags are valid, then issue one four-pixel neighborhood to `bilinear_interp`. Preserve invalid-coordinate black output and SOF/EOL markers.

- [ ] **Step 4: Run the image-level cached regression and compare traffic counters.**

Expected: pixel output matches the existing golden image, single-pixel DDR requests are zero in cached mode, source DDR accesses are four-beat row bursts, and output stalls occur only on Tile misses or explicit backpressure.

- [ ] **Step 5: Run existing image tests and commit.**

```powershell
python -m unittest discover -s tests -p "test_*.py" -v
powershell -ExecutionPolicy Bypass -File sim/run_mes50hp_top_image.ps1
git add rtl/memory/cached_pixel_fetch_engine.sv rtl/interpolation/bilinear_interp.sv rtl/distortion/distortion_image_pipeline.sv rtl/board/mes50hp/mes50hp_top.sv sim/tb_cached_pixel_fetch_engine.sv sim/run_cached_pixel_fetch_engine.ps1
git commit -m "feat: integrate cached pixel fetch with bilinear output"
```

### Task 7: Add 1080P30 video mode and RGBX8888 Ping-Pong frame buffers

**Files:**
- Create: `rtl/board/mes50hp/video_mode_1080p30.sv`
- Modify: `rtl/board/mes50hp/pgl50h_board_top.sv`
- Modify: `rtl/board/mes50hp/algorithm_frame_writer.sv`
- Modify: `rtl/board/mes50hp/ddr3_frame_reader.sv`
- Modify: `rtl/board/mes50hp/board_video_control.sv`
- Modify: `sim/tb_algorithm_frame_writer.sv`
- Modify: `sim/tb_ddr3_frame_reader.sv`
- Create: `sim/tb_video_mode_1080p30.sv`
- Create: `sim/run_video_mode_1080p30.ps1`

**Interfaces:**
- `video_mode_1080p30` produces `hs`, `vs`, `de`, `x`, `y`, and `frame_start` at 74.25 MHz using totals H=2200 and V=1125.
- Frame writers/readers use 32-bit RGBX words and 256-bit DDR bursts.
- Board parameters become `IMAGE_WIDTH=1920`, `IMAGE_HEIGHT=1080`, `PIXEL_BYTES=4`, and separate input/output frame bases.

- [ ] **Step 1: Write timing and frame-packing tests.**

Assert exactly 2200 pixel-clock positions per line, 1125 lines per frame, 1920×1080 active DE positions, one frame-start pulse, and eight RGBX words per 256-bit write beat.

- [ ] **Step 2: Run timing tests and confirm the new mode is absent or still fixed at 720P.**

```powershell
powershell -ExecutionPolicy Bypass -File sim/run_video_mode_1080p30.ps1
```

- [ ] **Step 3: Implement the parameterized 1080P30 timing wrapper.**

Keep vendor HDMI initialization unchanged. Put only mode timing and user data packing in project-owned files. Do not modify the imported vendor `sync_vg.v` in place.

- [ ] **Step 4: Update frame writer/reader and control sequencing.**

Capture one complete RGBX input frame, process only a complete Ping-Pong input frame, write the corrected RGBX output frame, and display only a complete output frame. Add explicit frame-base toggles synchronized into the core and video domains.

- [ ] **Step 5: Run board-structure and frame-buffer regressions.**

```powershell
powershell -ExecutionPolicy Bypass -File sim/run_algorithm_frame_writer.ps1
powershell -ExecutionPolicy Bypass -File sim/run_ddr3_frame_reader.ps1
powershell -ExecutionPolicy Bypass -File sim/run_pgl50h_board_top_compile.ps1
```

- [ ] **Step 6: Commit the board mode milestone.**

```powershell
git add rtl/board/mes50hp sim/tb_algorithm_frame_writer.sv sim/tb_ddr3_frame_reader.sv sim/tb_video_mode_1080p30.sv sim/run_video_mode_1080p30.ps1
git commit -m "feat: add 1080p30 RGBX frame path"
```

### Task 8: Prove full-frame 1080P30 throughput under DDR contention

**Files:**
- Modify: `sim/models/ddr_behavior_model.sv`
- Create: `sim/tb_1080p30_throughput.sv`
- Create: `sim/run_1080p30_throughput.ps1`
- Create: `docs/reports/1080p30_throughput_report.md`

**Interfaces:**
- DDR model exposes counters for command count, 256-bit beats, source bytes, input-write bytes, output-write bytes, display-read bytes, stalls, underflows, and overflows.
- The throughput testbench accepts `CLK_HZ=100_000_000`, `FPS=30`, and `FRAME_WIDTH=1920`, `FRAME_HEIGHT=1080`.

- [ ] **Step 1: Write assertions for the frame budget and no data loss.**

```systemverilog
assert (frame_cycles <= 3333333);
assert (output_pixel_count == 1920 * 1080);
assert (!input_underflow && !output_underflow);
assert (!coordinate_fifo_overflow && !coordinate_fifo_underflow);
```

- [ ] **Step 2: Run the throughput test against the current cached path.**

```powershell
powershell -ExecutionPolicy Bypass -File sim/run_1080p30_throughput.ps1
```

Expected initial failure: the cached path may exceed the frame budget under the worst configured DDR latency. Record the measured miss penalty before changing RTL.

- [ ] **Step 3: Add only the smallest required latency-hiding mechanism.**

If the frame budget fails, first add a Tile Fill request FIFO and two outstanding row reads. Keep display-read priority and preserve the same cache data format. Do not increase the algorithm clock before measuring the cache and DDR stalls.

- [ ] **Step 4: Re-run with three distortion models and contention.**

Run identity, barrel, and pincushion maps with 3–11 cycle variable read latency, periodic command backpressure, and simultaneous input/output/display traffic. Require frame cycles ≤3,333,333, no FIFO errors, source traffic ≤10 MB/frame, and no output mismatches.

- [ ] **Step 5: Save the report and commit.**

```powershell
git add sim/models/ddr_behavior_model.sv sim/tb_1080p30_throughput.sv sim/run_1080p30_throughput.ps1 docs/reports/1080p30_throughput_report.md
git commit -m "test: verify 1080p30 throughput budget"
```

### Task 9: Run PDS synthesis, timing, and resource gates

**Files:**
- Modify: `pds/pgl50h_rtl_synth/pgl50h_rtl_synth.pds`
- Modify: `constraints/mes50hp/pgl50h_board_top.fdc`
- Create: `docs/reports/2026-10-02-1080p30-pds-results.md`

- [ ] **Step 1: Run the vendor-neutral RTL simulation suite before PDS.**

```powershell
python -m unittest discover -s tests -p "test_*.py" -v
powershell -ExecutionPolicy Bypass -File sim/run_1080p30_throughput.ps1
```

- [ ] **Step 2: Import the cached RTL and 1080P30 board sources into the existing PDS project.**

Keep DDR3/PLL IP generated by the installed PDS version. Do not copy a different PDS version's generated implementation directory into the project.

- [ ] **Step 3: Run PDS synthesis and record LUT6, FF, DRM, APM, Fmax, and critical paths.**

The 100 MHz algorithm clock must meet timing. The report must separately identify failures in vendor DDR/HDMI generated clocks and failures in project-owned algorithm/cache paths.

- [ ] **Step 4: If timing fails, fix the worst project-owned path in this order.**

Pipeline Tag comparison and Tile-way selection first, register the four-bank output mux second, pipeline Tile-fill unpacking third, and only then retune the distortion arithmetic. Do not reduce cache capacity or return to single-pixel DDR reads solely to hide a timing report.

- [ ] **Step 5: Save the PDS report and commit only curated reports and project sources.**

```powershell
git add pds/pgl50h_rtl_synth/pgl50h_rtl_synth.pds constraints/mes50hp/pgl50h_board_top.fdc docs/reports/2026-10-02-1080p30-pds-results.md
git commit -m "build: close 1080p30 PDS timing baseline"
```

## Completion Checklist

- [ ] Full 1920×1080 fixed-point map and physical DDR traffic report are reproducible.
- [ ] RGBX8888 address and burst behavior is covered by unit tests.
- [ ] Coordinate FIFO, burst reader, Tile Cache, and cached Pixel Fetch each have focused RTL tests.
- [ ] Cached output matches the Python golden image on small and full-frame tests.
- [ ] 1080P30 timing and Ping-Pong frame buffers pass board-structure simulation.
- [ ] Full-frame throughput stays within 3,333,333 cycles at 100 MHz under modeled DDR contention.
- [ ] PDS resource and timing results are recorded; generated build directories remain untracked.

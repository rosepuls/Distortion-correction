# PGL50H Reset Routability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the 1280x720@30 RGBX-cache image pipeline while removing the large asynchronous-reset routing cone that prevents PGL50H detailed routing from converging.

**Architecture:** The current synthesis result has only 36.30% LUT, 15.06% register, 36.94% DRM18K, and 50.00% APM utilization, but `algorithm_system.core_rst_n` drives 4,383 asynchronous-reset pins.  Split this signal into reset leaves located at functional boundaries, and make FIFO/cache payload storage reset-safe by resetting validity, pointers, and state rather than every stored data bit.  The existing frame-start cache invalidation remains the mechanism that retires prior-frame cache contents.

**Tech Stack:** SystemVerilog RTL, XSim image/unit regressions, Pango PDS 2022.2-SP6.4 reports.

## Global Constraints

- Keep `pgl50h_board_top` at 1280x720@30 and retain the 37.125 MHz video pixel-clock definition.
- Preserve `cached_pixel_fetch_engine` request/response throughput and the 720p30 target of one image frame within 2,500,000 core-clock cycles.
- Do not change DDR3 IP-generated RTL, pin assignments, or DDR PHY placement constraints.
- Do not use `set_false_path`, weaker clock constraints, or larger router iteration limits to hide the physical problem.
- The agent does not run PDS synthesis or Place & Route; PDS-derived checks are run by the user after implementation.
- Do not create a Git commit unless the user explicitly asks.

---

### Task 1: Add a PDS-artifact fanout acceptance check

**Files:**
- Create: `sim/check_pgl50h_algorithm_reset_fanout.ps1`
- Test input: `boards/pgl50h/pds/pgl50h_rtl_synth/synthesize/pgl50h_board_top_controlsets.txt`

**Interfaces:**
- Consumes: PDS-generated `Number of DFF:CP Signals` report section.
- Produces: exit code 0 only when the monolithic `algorithm_system.core_rst_n` reset cone no longer exceeds 512 loads and no algorithm reset leaf exceeds 1024 loads.

- [x] **Step 1: Write the failing acceptance check**

```powershell
$report = Get-Content -LiteralPath $controlSetReport -Raw
if ($report -match '~algorithm_system\.core_rst_n.*:\s+(\d+)' -and [int]$matches[1] -gt 512) {
    throw "FAIL: monolithic algorithm reset fanout is $($matches[1]), expected <= 512"
}
```

The production condition this catches is retaining a single reset driver for every Cache/FIFO/register payload element.  The current report must fail because it reports 4,383 loads.

- [x] **Step 2: Run the check against the current report**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\check_pgl50h_algorithm_reset_fanout.ps1`

Expected: `FAIL` mentioning the existing 4,383-load `algorithm_system.core_rst_n` reset cone.

- [x] **Step 3: Keep the check report-driven**

Do not inspect RTL text.  The assertion must consume the PDS netlist report so it measures the physical optimization objective rather than source formatting.

### Task 2: Introduce reset leaves at algorithm functional boundaries

**Files:**
- Create: `rtl/platform/common/control/algorithm_reset_tree.sv`
- Modify: `rtl/algorithm/distortion/distortion_image_pipeline.sv`
- Modify: `rtl/platform/common/memory/cached_pixel_fetch_engine.sv`
- Modify: `rtl/algorithm/distortion/distortion_core_optimized.sv`
- Modify: `boards/pgl50h/pds/pgl50h_rtl_synth/pgl50h_rtl_synth.pds`
- Modify: `boards/pgl50h/pds/pgl50h_rtl_synth/impl.tcl`
- Test: `sim/tb_distortion_pipeline_fifo_decouple.sv`
- Test command: `sim/run_distortion_pipeline_fifo_decouple.ps1`

**Interfaces:**
- Consumes: one active-low algorithm reset and the existing `clk`.
- Produces: `geometry_rst_n`, `fifo_rst_n`, `fetch_control_rst_n`, and `fetch_storage_rst_n`; each is asynchronously asserted and synchronously released in the same core-clock domain.

- [x] **Step 1: Extend the pipeline reset test first**

Add a reset-deassertion case that keeps `in_valid=0` until all reset leaves are released, then injects a known coordinate sequence and asserts that the first accepted coordinate is marked SOF and produces exactly one output.  The test must fail before the leaf-reset interface exists because the leaf-release observation is unavailable.

```systemverilog
wait (dut.geometry_rst_n && dut.fifo_rst_n && dut.fetch_control_rst_n);
send_pixel(1'b1, 1'b1, 13'd0, 13'd0);
expect_single_sof_output();
```

- [x] **Step 2: Verify the new test fails for the missing interface**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\run_distortion_pipeline_fifo_decouple.ps1`

Expected: compile failure identifying the missing reset-leaf signal; do not proceed if it fails for another reason.

- [x] **Step 3: Implement the minimal reset tree**

```systemverilog
module algorithm_reset_tree (
    input wire clk, input wire reset_n,
    output wire geometry_rst_n, output wire fifo_rst_n,
    output wire fetch_control_rst_n, output wire fetch_storage_rst_n
);
    mes50hp_reset_sync geometry_sync (.clk(clk), .reset_n(reset_n), .rst_n(geometry_rst_n));
    mes50hp_reset_sync fifo_sync     (.clk(clk), .reset_n(reset_n), .rst_n(fifo_rst_n));
    mes50hp_reset_sync control_sync  (.clk(clk), .reset_n(reset_n), .rst_n(fetch_control_rst_n));
    mes50hp_reset_sync storage_sync  (.clk(clk), .reset_n(reset_n), .rst_n(fetch_storage_rst_n));
endmodule
```

Wire the leaves to geometry, FIFO, fetch-control, and Cache-storage subtrees; do not change pixel/data interfaces or add a clock domain.

- [x] **Step 4: Run the pipeline test and compile regression**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\run_distortion_pipeline_fifo_decouple.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\run_pgl50h_board_top_compile.ps1
```

Expected: both report `TEST_PASS`.

### Task 3: Remove unnecessary payload resets from the Cache/FIFO data plane

**Files:**
- Modify: `rtl/platform/common/memory/coordinate_fifo.sv`
- Modify: `rtl/platform/common/memory/cached_pixel_fetch_engine.sv`
- Modify: `rtl/platform/common/memory/pixel_tile_cache.sv`
- Modify: `rtl/platform/common/memory/ddr_burst_reader.sv` only if it resets payload memories rather than transaction-valid state
- Modify: `rtl/algorithm/interpolation/bilinear_interp.sv` only if it resets pixel operands rather than output-valid state
- Test: `sim/tb_coordinate_fifo.sv`
- Test: `sim/tb_pixel_tile_cache.sv`
- Test: `sim/tb_cached_pixel_fetch_engine.sv`

**Interfaces:**
- Consumes: local reset leaves and the existing `frame_start` / `invalidate` pulses.
- Produces: identical ready/valid behavior; stored payload values are ignored until their validity or queue count establishes ownership.

- [x] **Step 1: Add the stale-payload regression before changing storage reset logic**

In the Cache test, fill a tile with a nonzero known value, assert reset, then issue a lookup before a new fill.  Assert that no stale response is emitted; after the following fill, assert the response equals the new literal pixel value.  The test must reject an implementation that forgets to clear validity while leaving payload RAM untouched.

```systemverilog
fill_tile(12'd4, 12'd8, 24'h12_34_56);
pulse_reset();
expect_no_response_for(12'd4, 12'd8);
fill_tile(12'd4, 12'd8, 24'hAB_CD_EF);
lookup_and_check(12'd4, 12'd8, 24'hAB_CD_EF);
```

- [x] **Step 2: Verify the test fails after a deliberate one-line validity mutation in a temporary working copy, then revert that mutation**

The expected failure is a stale cache response.  This demonstrates the test catches the real bug that payload-reset removal could introduce; no temporary mutation is retained.

- [x] **Step 3: Implement validity-only reset semantics**

For each queue/cache:

```systemverilog
if (!rst_n) begin
    wr_ptr <= '0;
    rd_ptr <= '0;
    count  <= '0;
    valid_bits <= '0;
    // Do not assign payload arrays, tags, interpolator operands, or RAM data here.
end
```

Keep Cache tag/data entries invalid until the existing set-by-set `invalidate` process or a completed fill marks them valid.  Keep FIFO output invalid while `count == 0`; payload RAM may retain arbitrary bits.

- [x] **Step 4: Run focused memory regressions**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\run_coordinate_fifo.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\run_pixel_tile_cache.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\run_pixel_tile_cache_packed.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\run_pixel_tile_cache_plru.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\run_cached_pixel_fetch_engine.ps1
```

Expected: every test reports `TEST_PASS`.

### Task 4: Verify full 720p function and throughput, then hand PDS back to the user

**Files:**
- Modify: `rtl/guide/畸变矫正图像与板载仿真流程.md`
- Modify: `rtl/guide/RTL模块总览.md`
- Test command: `sim/run_720p30_throughput.ps1`
- Test command: `sim/run_mes50hp_top_cache_image_720p.ps1`

**Interfaces:**
- Consumes: unchanged 1280x720 image assets and the PDS project source list.
- Produces: exact golden RGB888 image match, a frame throughput result below 2,500,000 core cycles, and user-run PDS fanout evidence.

- [x] **Step 1: Run full behavioral and throughput regressions**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\run_720p30_throughput.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\run_mes50hp_top_cache_image_720p.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\run_pgl50h_board_top_compile.ps1
```

Expected: 720p output exactly matches the golden RGB888 image, all 921,600 pixels complete, and frame cycles remain below 2,500,000.

- [x] **Step 2: Update the two RTL guides**

Document that image payload RAM is intentionally not reset, list the validity/pointer ownership rule, and state that the Cache is invalidated once per source frame.

- [ ] **Step 3: User runs PDS and the acceptance check**

The user reopens `boards/pgl50h/pds/pgl50h_rtl_synth/pgl50h_rtl_synth.pds`, runs Compile and Synthesize, then runs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\sim\check_pgl50h_algorithm_reset_fanout.ps1
```

Only then run Place & Route.  Success criterion: the check passes and detailed routing reaches zero unrouted nets; timing is evaluated only after routing completes.

## Self-Review

- The plan addresses the observed 4,383-load asynchronous reset net and the non-converging detailed router, rather than masking timing with false paths.
- It leaves resolution, cache associativity, DDR3 IP, and throughput architecture unchanged.
- Every RTL behavior change has a unit or integration regression; PDS physical fanout is checked from a generated netlist report.
- No step depends on board hardware.

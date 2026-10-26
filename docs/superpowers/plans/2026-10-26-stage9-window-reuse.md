# Stage 9 Horizontal Window Reuse Implementation Plan

> **For agentic workers:** Inline execution in the current task; the checklist tracks the implementation and verification sequence.

**Goal:** Reduce Stage 9 bicubic reader cache lookups for adjacent horizontal source windows in a separate test project.

**Architecture:** Clone the Brown-fixed Stage 9 project without generated PDS output. Preserve the last completed 4×4 stencil. When the next valid stencil has `x0 = previous_x0 + 1` and the same `y0`, shift the previous sample window and fetch the new right edge with two 2×2 cache lookups. Fall back to the existing four-lookup path on every other coordinate transition.

**Tech Stack:** SystemVerilog, Vivado Simulator 2020.2, Pango PDS 2022.2-SP6.4, PowerShell.

## Global Constraints

- Do not modify `stage9_bicubic_catmull_rom_brown_fix_test`, Stage 8, or the original Stage 9 project.
- Preserve the Brown mapper, Catmull–Rom arithmetic, 4×4 strict border rule, metadata ordering, cache/DDR interface, and valid/ready semantics.
- Reuse is legal only for valid geometry with an exactly adjacent horizontal integer source origin and unchanged vertical origin.
- Every unsupported transition must use the original four-query gather.
- Board FPS and image quality remain unverified until the user measures this project's matching `.sbit/.fic` pair.

---

### Task 1: Create the isolated project and a failing reuse regression

**Files:**
- Create: `fpga/project/stage9_bicubic_catmull_rom_window_reuse_test/` from Brown-fix source/configuration, excluding generated PDS directories and old bitstream/FIC outputs.
- Modify: `fpga/project/stage9_bicubic_catmull_rom_window_reuse_test/sim/cached_bicubic_neighbor_reader_tb.sv`

- [x] Assert exact sample correctness for a full-window baseline and the immediately adjacent horizontal window.
- [x] Measure the response latency for both cache-hit requests and require the reused request to complete sooner.
- [x] Run `sim/Run-Stage9BicubicReader.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2'` and observe the expected failure: both paths currently take 28 cycles.

### Task 2: Implement safe horizontal stencil reuse

**Files:**
- Modify: `fpga/project/stage9_bicubic_catmull_rom_window_reuse_test/source/rtl/memory/cached_bicubic_neighbor_reader.sv`

- [ ] Track whether a completed valid 4×4 window may be reused and its integer origin.
- [ ] On exact `x0 + 1`, same `y0`, and full 4×4 validity, shift three existing columns left and issue only the two cache queries for the new rightmost column.
- [ ] Assemble returned pixels at column 3; keep row-major sample order and metadata unchanged.
- [ ] Keep the original four-query path for non-adjacent x, changed y, invalid geometry, and first requests.
- [ ] Invalidate reuse state on a source-frame start and after an invalid-geometry response; preserve output stability under backpressure.
- [ ] Re-run the reader simulation and require exact pixels plus lower reused-window latency.

### Task 3: Integrate, verify the full frame, and record build results

**Files:**
- Verify: `fpga/project/stage9_bicubic_catmull_rom_window_reuse_test/HDMI_IN_DDR3_HDMI_OUT.pds`
- Modify: `fpga/project/stage9_bicubic_catmull_rom_window_reuse_test/README.md`
- Create: `docs/results/stage9-bicubic-window-reuse.md`

- [ ] Run the existing 1280×720 Stage 9 full-frame simulation and compare it with the Brown-fix baseline behavior.
- [ ] Run the complete Stage 9 PDS flow; record routed setup/hold results, resources, and paired `.sbit/.fic` SHA-256 values if it completes.
- [ ] Update the new project README with the reuse condition, fallback behavior, commands, and measured (or explicitly not-yet-measured) board status.
- [ ] State that only a same-condition board comparison with this project's paired artifacts establishes FPS improvement.

# 720p30 Cache Resource Reduction Implementation Plan

> **For agentic workers:** Execute the tasks in order and verify each task before moving to the next.

**Goal:** 将 PGL50H 畸变矫正路径切换为 1280×720@30fps，并通过 16×4 Tile Cache 降低 PGL50H 的存储和布线压力。

**Architecture:** 保持 100 MHz 算法时钟、RGBX8888 DDR 输入和 256-bit burst 接口不变。将视频时序、图像资产和算法参数切换到 720p，同时把 Cache Bank 从固定 2048×128 改为配置化深度，目标为 16 set × 4 way、512×128/Bank。

**Tech Stack:** SystemVerilog RTL、PGL50H vendor RAM wrapper、PowerShell、Python image/memory utilities、XSim。

## Global Constraints

- 不执行 PDS 综合、布局布线或 PLL 生成。
- 720p 主路径固定为 1280×720@30fps。
- 算法时钟保持 100 MHz，30fps 周期预算为 3,333,333。
- 保持四个 128-bit Cache Bank 和 256-bit DDR burst 接口。
- 保留 1080p 回归文件和结果，不覆盖历史基线。

### Task 1: Parameterize and shrink the Tile Cache banks

**Files:**
- Modify: `rtl/platform/common/memory/tile_cache_bank_ram.sv`
- Modify: `rtl/platform/common/memory/pixel_tile_cache.sv`
- Modify: `rtl/vendor/pgl50h/memory/pgl50h_tile_cache_bank_ip.v`
- Modify: `sim/pgl50h_tile_cache_bank_ip_model.sv`

- [x] Replace fixed 11-bit bank addresses with a parameterized `BANK_ADDR_WIDTH` and pass the 16×4 target depth through all four bank instances.
- [x] Keep `BANK_WORDS_PER_TILE=8` and calculate `BANK_WORD_COUNT=SET_COUNT*WAYS*BANK_WORDS_PER_TILE`.
- [x] Set the target vendor RAM geometry to 512×128 for the 16×4 configuration and preserve synchronous one-cycle read behavior.
- [x] Add 4-way PLRU state handling with 3 bits per set and remove use of 8-way-only PLRU assumptions.
- [x] Keep fill address, bank lane mapping, retry, invalidate and response FIFO protocols unchanged.
- [x] Run the cache unit scripts and confirm no address truncation or out-of-range bank access occurs.

### Task 2: Switch the board path to 720p30

**Files:**
- Create: `rtl/board/pgl50h/video_mode_720p30.sv`
- Modify: `rtl/board/pgl50h/pgl50h_board_top.sv`
- Modify: `rtl/board/pgl50h/mes50hp_top.sv`
- Modify: `boards/pgl50h/constraints/pgl50h_board_top.fdc`

- [x] Set board and algorithm defaults to `IMAGE_WIDTH=1280` and `IMAGE_HEIGHT=720`.
- [x] Set Cache parameters to `TILE_CACHE_SET_COUNT=16` and `TILE_CACHE_WAYS=4`.
- [x] Set 720p camera/algorithm parameters to `fx=fy=600`, `cx=639.5`, and `cy=359.5` in the existing fixed-point formats.
- [x] Add the 1650×750 720p30 timing generator with 37.125 MHz pixel-clock assumptions.
- [x] Replace the board timing instance with the 720p30 module while leaving the 1080p timing module available for legacy tests.
- [x] Update the constraint comments and clock targets to 37.125 MHz; do not modify generated PLL contents in this task.
- [x] Run static source and parameter checks without invoking PDS.

### Task 3: Add 720p image and throughput regression entry points

**Files:**
- Create: `sim/run_mes50hp_top_cache_image_720p.ps1`
- Create: `sim/tb_mes50hp_top_cache_image_720p.sv`
- Create: `sim/run_720p30_throughput.ps1`
- Create: `sim/tb_720p30_throughput.sv`
- Modify: `software/sim_assets/README.md`

- [x] Generate 1280×720 checkerboard and distorted RGB888 input assets.
- [x] Use scaled camera parameters and write all outputs under `result/sim_assets/cache_full_chain_1280x720`.
- [x] Compile the actual cache-enabled algorithm path with 16 sets and 4 ways.
- [x] Check exact output dimensions, frame completion, line endings and pixel-by-pixel golden equality.
- [x] Measure algorithm cycles and fail if they exceed 2,500,000.
- [x] Keep the existing 1080p scripts unchanged and document the 720p entry points.

### Task 4: Update documentation and project source checks

**Files:**
- Modify: `rtl/board/pgl50h/README.md`
- Modify: `rtl/guide/RTL模块总览.md`
- Modify: `rtl/guide/畸变矫正图像与板载仿真流程.md`
- Modify: `docs/board/pgl50h_pds_handoff.md`
- Modify: relevant `sim/check_*.ps1` source and resource checks

- [x] Document 720p as the active board target and 1080p as legacy regression.
- [x] Document the 16×4 Cache geometry and the required PDS PLL regeneration to 37.125 MHz.
- [x] Ensure source-list checks include the 720p timing module and do not require PDS execution.
- [x] Record expected resource comparison points for the user’s PDS report.

### Task 5: Verification and handoff

**Files:**
- Modify: only generated local result files under `result/sim_assets/cache_full_chain_1280x720`

- [x] Run RTL syntax/structural checks.
- [x] Run cache and DDR unit regressions.
- [x] Run the 720p full-chain image regression.
- [x] Run the 720p throughput regression.
- [x] Report exact output paths, cycle count and any remaining PDS-only action.

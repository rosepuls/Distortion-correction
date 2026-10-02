# PGL50H HDMI + DDR3 Board Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a PGL50H physical board top that receives MS7200 RGB888 video, stores it through the official DDR3 controller path, feeds the existing `mes50hp_top` through a random pixel-read adapter, and outputs the corrected RGB888 stream to MS7210.

**Architecture:** Retain the existing algorithm RTL untouched. Reuse the official DDR3 controller/PHY (`DDR3_50H`), HDMI I2C initialization modules, the 24-bit input `wr_buf` path and `wr_rd_ctrl_top` command controller. A random-read adapter serves `mes50hp_top`; its non-contiguous result stream is repacked into a separate DDR3 output frame, then a fixed-timing reader continuously supplies MS7210. The first board version captures and processes one frame after reset, then loops that corrected frame for stable hardware bring-up.

**Tech Stack:** SystemVerilog / Verilog-2001, Pango PDS 2022.1 reference IP, PDS 2022.2-SP6.4 target flow, XSIM structural and RTL simulation.

## Global Constraints

- Target board: MES50HP carrying PGL50H; physical ports and electrical constraints derive only from `board_reference/mes50hp/06_hdmi_loop` and `board_reference/mes50hp/10_HDMI_DDR3_OV5640_test`.
- The new physical top is `pgl50h_board_top`; `mes50hp_top` stays an internal logical algorithm module.
- HDMI RX is MS7200 RGB888 from `06_hdmi_loop`; `10_HDMI_DDR3_OV5640_test` is a camera-input reference and must not introduce camera ports into the new top.
- Use `PIX_WIDTH=24`, with input and algorithm pixel packing `{r, g, b}`.
- No runtime calibration registers in this change; all ten `cfg_*` values are fixed parameters/localparams in the board wrapper.
- Vendor source copied into the project is a mechanical reference import; do not edit reference files in `board_reference`.
- Do not edit `pds/pgl50h_rtl_synth/pgl50h_rtl_synth.pds` in this plan. The user will add source files, select the top and apply the final FDC in PDS after receiving instructions.
- This workspace is not a Git repository, so no commit steps are possible.

---

### Task 1: Preserve and index official board references

**Files:**
- Create: `board_reference/mes50hp/README.md`
- Create: `docs/board/pgl50h_official_reference_map.md`
- Read: `board_reference/mes50hp/06_hdmi_loop/src/hdmi_loop.v`
- Read: `board_reference/mes50hp/06_hdmi_loop/src/hdmi_loop.fdc`
- Read: `board_reference/mes50hp/07_ddr3_test/ipcore/ddr3_test/ddr3_test.v`
- Read: `board_reference/mes50hp/10_HDMI_DDR3_OV5640_test/source/rtl/hdmi_ddr_ov5640_top.v`
- Read: `board_reference/mes50hp/10_HDMI_DDR3_OV5640_test/source/rtl/DDR3_50H/DDR3_50H.v`
- Read: `board_reference/mes50hp/10_HDMI_DDR3_OV5640_test/hdmi_ddr_ov5640_top.fdc`

**Interfaces:**
- Consumes: the three extracted official demo directories.
- Produces: a path/port/constraint manifest used by every later task.

- [x] **Step 1: Write the failing manifest check**

Create `sim/check_board_reference_files.ps1` with required paths and fail if any are missing:

```powershell
$required = @(
  'board_reference/mes50hp/06_hdmi_loop/src/hdmi_loop.v',
  'board_reference/mes50hp/06_hdmi_loop/src/hdmi_loop.fdc',
  'board_reference/mes50hp/07_ddr3_test/ipcore/ddr3_test/ddr3_test.v',
  'board_reference/mes50hp/10_HDMI_DDR3_OV5640_test/source/rtl/DDR3_50H/DDR3_50H.v',
  'board_reference/mes50hp/10_HDMI_DDR3_OV5640_test/hdmi_ddr_ov5640_top.fdc'
)
$required | ForEach-Object { if (-not (Test-Path $_)) { throw "Missing official reference: $_" } }
```

- [x] **Step 2: Run the check**

Run: `powershell -ExecutionPolicy Bypass -File .\sim\check_board_reference_files.ps1`

Expected: PASS after the three archives are present; a removed required file must report its exact missing path.

- [x] **Step 3: Write the manifest**

Record these verified physical ports from the official top/FDC: `sys_clk`, `pixclk_in`, `vs_in`, `hs_in`, `de_in`, `r_in[7:0]`, `g_in[7:0]`, `b_in[7:0]`, `iic_scl`, `iic_sda`, `iic_tx_scl`, `iic_tx_sda`, `pixclk_out`, `vs_out`, `hs_out`, `de_out`, `r_out[7:0]`, `g_out[7:0]`, `b_out[7:0]`, `mem_*`, `led_int`, `ddr_init_done`, and `heart_beat_led`.

- [x] **Step 4: Re-run the check and inspect the manifest**

Run: `powershell -ExecutionPolicy Bypass -File .\sim\check_board_reference_files.ps1`

Expected: PASS; manifest identifies `06_hdmi_loop` as HDMI RX source and `10_HDMI_DDR3_OV5640_test` as DDR3/HDMI TX source.

### Task 2: Import vendor-supported RTL without coupling to reference paths

**Files:**
- Create: `rtl/vendor/mes50hp/hdmi/`
- Create: `ip/pango/DDR3_50H/`
- Create: `rtl/vendor/mes50hp/README.md`
- Copy from: `board_reference/mes50hp/06_hdmi_loop/src/{iic_dri.v,ms7200_ctl.v,ms7210_ctl.v,ms72xx_ctl.v}`
- Copy from: `board_reference/mes50hp/10_HDMI_DDR3_OV5640_test/source/rtl/DDR3_50H/`
- Copy from: `board_reference/mes50hp/10_HDMI_DDR3_OV5640_test/source/rtl/{wr_buf.v,wr_fram_buf/,wr_rd_ctrl_top.v,wr_cmd_trans.v,wr_ctrl.v,rd_ctrl.v}`

**Interfaces:**
- Consumes: pinned reference source files from Task 1.
- Produces: project-local vendor modules `ms72xx_ctl`, `wr_buf`, `wr_rd_ctrl_top`, and `DDR3_50H`.

- [x] **Step 1: Write the failing vendor-source inventory check**

Create `sim/check_pgl50h_vendor_import.ps1` to require `rtl/vendor/mes50hp/hdmi/ms72xx_ctl.v`, `rtl/vendor/mes50hp/ddr/wr_buf.v`, `rtl/vendor/mes50hp/ddr/wr_rd_ctrl_top.v`, and `ip/pango/DDR3_50H/DDR3_50H.v`.

- [x] **Step 2: Run the check before copying**

Run: `powershell -ExecutionPolicy Bypass -File .\sim\check_pgl50h_vendor_import.ps1`

Expected: FAIL naming the missing project-local vendor paths.

- [x] **Step 3: Mechanically copy the selected vendor source trees**

Preserve file names and relative subdirectories. Do not copy `hdmi_ddr_ov5640_top.v`, `fram_buf.v`, camera configuration modules, or archived PDS reports into `rtl/vendor`.

- [x] **Step 4: Add a provenance README**

State each copied directory’s originating archive, relative source path and PDS 2022.1 generation version. State that `DDR3_50H` must be regenerated under the installed PDS version before board programming.

- [x] **Step 5: Re-run the inventory check**

Run: `powershell -ExecutionPolicy Bypass -File .\sim\check_pgl50h_vendor_import.ps1`

Expected: PASS.

### Task 3: Implement and verify the random DDR3 pixel-read adapter

**Files:**
- Create: `sim/tb_ddr3_pixel_read_adapter.sv`
- Create: `rtl/board/mes50hp/ddr3_pixel_read_adapter.sv`
- Create: `sim/run_ddr3_pixel_read_adapter.ps1`

**Interfaces:**
- Consumes: `mes50hp_top` logical read signals `mem_req_valid`, `mem_req_addr[31:0]`, `mem_rsp_ready` and 256-bit data returns from `wr_rd_ctrl_top`.
- Produces: `mem_req_ready`, `mem_rsp_valid`, `mem_rsp_data[23:0]`, `rd_cmd_en`, `rd_cmd_addr[27:0]`, `rd_cmd_len[31:0]`, and `rd_data_ready`.
- Address conversion: for logical RGB888 pixel index `p`, request the 32-bit-word address `floor((p * 3) / 4)`; retain the enclosing 256-bit return beat and extract the consecutive 24-bit `{r,g,b}` field, including a field crossing a 32-bit-word boundary.

- [x] **Step 1: Write the failing testbench**

In `tb_ddr3_pixel_read_adapter.sv`, emulate a command/response backend that returns a 256-bit beat holding eight known RGB888 pixels. Drive pixel requests for indices `0`, `1`, `3`, and the index whose 24-bit field crosses a 32-bit word boundary. Assert each response byte-for-byte:

```systemverilog
if (rsp_data !== 24'h11_22_33) $fatal(1, "pixel 0 mismatch");
if (rsp_data !== 24'h44_55_66) $fatal(1, "pixel 1 mismatch");
if (rsp_data !== 24'hAA_BB_CC) $fatal(1, "cross-word pixel mismatch");
```

- [x] **Step 2: Run before creating the adapter**

Run: `powershell -ExecutionPolicy Bypass -File .\sim\run_ddr3_pixel_read_adapter.ps1`

Expected: FAIL because `ddr3_pixel_read_adapter` does not exist.

- [x] **Step 3: Implement the minimal adapter FSM**

Implement states `IDLE`, `ISSUE_CMD`, `WAIT_DATA`, `RESPOND`. Accept one logical request only when no response is pending. Issue `rd_cmd_len = 32'd1`, wait for a 256-bit data-valid pulse, extract the requested packed RGB888 field, then hold `mem_rsp_valid` until `mem_rsp_ready` is high. Cache a returned beat only when its 256-bit-aligned address matches the next requested pixel’s address range.

- [x] **Step 4: Run the adapter test**

Run: `powershell -ExecutionPolicy Bypass -File .\sim\run_ddr3_pixel_read_adapter.ps1`

Expected: PASS, with all four pixel assertions and a stalled `mem_rsp_ready` handshake covered.

### Task 4: Implement board-frame control and integrate `mes50hp_top`

**Files:**
- Create: `sim/tb_board_video_control.sv`
- Create: `rtl/board/mes50hp/board_video_control.sv`
- Create: `sim/run_board_video_control.ps1`

**Interfaces:**
- Consumes: `rx_vs`, `ddr_init_done`, `wr_frame_complete`, `algo_frame_done`.
- Produces: one-cycle `algo_frame_start`, `input_frame_locked`, `tx_select_algo`.
- Behavior: ignore HDMI input until DDR3 calibration completes; on a completed input frame issue exactly one `algo_frame_start`; while algorithm is busy keep the input frame locked; select corrected data after the first corrected output SOF.

- [x] **Step 1: Write the failing controller test**

Test these sequences: input VS before `ddr_init_done` produces no start; first post-calibration frame completion produces one start pulse; a second completion while busy produces no second pulse; `algo_frame_done` clears busy and permits exactly one next start.

- [x] **Step 2: Run before creating the controller**

Run: `powershell -ExecutionPolicy Bypass -File .\sim\run_board_video_control.ps1`

Expected: FAIL because `board_video_control` does not exist.

- [x] **Step 3: Implement the controller**

Synchronize frame-complete indication into the DDR/algorithm clock domain, edge-detect it, and use a three-state controller `WAIT_DDR`, `CAPTURE_COMPLETE`, `ALGO_RUNNING`. Register every output; no combinational crossing between `pixclk_in` and DDR clock.

- [x] **Step 4: Run the controller test**

Run: `powershell -ExecutionPolicy Bypass -File .\sim\run_board_video_control.ps1`

Expected: PASS for all timing sequences.

### Task 4A: Buffer the non-contiguous algorithm output in DDR3

**Files:**
- Create: `sim/tb_algorithm_frame_writer.sv`
- Create: `rtl/board/mes50hp/algorithm_frame_writer.sv`
- Create: `sim/run_algorithm_frame_writer.ps1`

**Behavior:** Accept every asserted `out_valid` regardless of gaps, preserve `{r,g,b}` byte order, pack each group of four pixels into the same three 32-bit words used by official `wr_buf`, and issue one DDR write command per complete line. Use two line banks so one line can drain while the next line fills. Set `overflow` if both banks are occupied when a new line starts.

### Task 4B: Read the corrected frame at fixed HDMI timing

**Files:**
- Create: `sim/tb_ddr3_frame_reader.sv`
- Create: `rtl/board/mes50hp/ddr3_frame_reader.sv`
- Create: `sim/run_ddr3_frame_reader.ps1`

**Behavior:** Issue one DDR burst per active line from a fixed corrected-frame base address, write returned 256-bit beats into the official dual-clock `rd_fram_buf`, and unpack RGB888 pixels in the HDMI pixel clock domain. Repeat the same corrected frame on every output `vs` without changing its base address.

### Task 5: Build the physical `pgl50h_board_top`

**Files:**
- Create: `sim/tb_pgl50h_board_top_compile.sv`
- Create: `rtl/board/mes50hp/pgl50h_board_top.sv`
- Create: `sim/run_pgl50h_board_top_compile.ps1`
- Create: `constraints/mes50hp/pgl50h_board_top.fdc`

**Interfaces:**
- Consumes: MS7200 input ports from `hdmi_loop.v`, DDR3 ports and clocking from `hdmi_ddr_ov5640_top.v`, project-local vendor IP from Task 2, and `mes50hp_top`.
- Produces: exactly the physical ports `sys_clk`, `iic_scl`, `iic_sda`, `iic_tx_scl`, `iic_tx_sda`, `pixclk_in`, `vs_in`, `hs_in`, `de_in`, `r_in[7:0]`, `g_in[7:0]`, `b_in[7:0]`, `pixclk_out`, `vs_out`, `hs_out`, `de_out`, `r_out[7:0]`, `g_out[7:0]`, `b_out[7:0]`, `mem_rst_n`, `mem_ck`, `mem_ck_n`, `mem_cke`, `mem_cs_n`, `mem_ras_n`, `mem_cas_n`, `mem_we_n`, `mem_odt`, `mem_a[14:0]`, `mem_ba[2:0]`, `mem_dqs[3:0]`, `mem_dqs_n[3:0]`, `mem_dq[31:0]`, `mem_dm[3:0]`, `hdmi_int_led`, `ddr_init_done`, and `heart_beat_led`.

- [x] **Step 1: Write the failing structural compile testbench**

Instantiate `pgl50h_board_top` with every physical port declared at its verified width. Compile it alongside `mes50hp_top`, `ddr3_pixel_read_adapter`, `board_video_control`, and simulation replacements for the DDR3 PHY and PLL. Check that no logical `cfg_*`, `mem_req_*`, `mem_rsp_*`, `frame_start`, or `frame_done` signal appears at the physical top.

- [x] **Step 2: Run before creating the board top**

Run: `powershell -ExecutionPolicy Bypass -File .\sim\run_pgl50h_board_top_compile.ps1`

Expected: FAIL because `pgl50h_board_top` does not exist.

- [x] **Step 3: Implement the board top**

Instantiate the imported `ms72xx_ctl`, generate `cfg_clk` and HDMI output pixel clock from the official PLL configuration, instantiate `wr_buf` with `PIX_WIDTH=24`, mux its input-frame write channel with `algorithm_frame_writer`, mux algorithm random reads with `ddr3_frame_reader`, connect the shared command controller to `DDR3_50H`, and instantiate `mes50hp_top`. Feed MS7210 only from the fixed-timing corrected-frame reader. Set all ten calibration constants as named parameters in the top with the current simulation constants as their default values.

- [x] **Step 4: Create the constraint file**

Copy the required HDMI, I2C, DDR3, LED, `sys_clk`, `pixclk_in`, and generated-clock definitions from the verified official `.fdc` files. Remove all OV5640/CMOS-only ports and constraints. Preserve DDR3 HSTL15/HSTL15D electrical attributes and all DDR PHY placement constraints exactly.

- [x] **Step 5: Run the structural compile test**

Run: `powershell -ExecutionPolicy Bypass -File .\sim\run_pgl50h_board_top_compile.ps1`

Expected: PASS with no undefined module, width mismatch, or accidental logical top-level IO.

### Task 6: Run regression and prepare the PDS handoff

**Files:**
- Modify: `rtl/board/mes50hp/README.md`
- Create: `docs/board/pgl50h_pds_handoff.md`
- Test: `sim/run_mes50hp_top_image.ps1`
- Test: `sim/run_ddr3_pixel_read_adapter.ps1`
- Test: `sim/run_board_video_control.ps1`
- Test: `sim/run_pgl50h_board_top_compile.ps1`

**Interfaces:**
- Consumes: complete Tasks 1–5 sources and tests.
- Produces: exact PDS source order, top selection, FDC import and expected verification steps for the user.

- [x] **Step 1: Run the unchanged algorithm regression**

Run: `powershell -ExecutionPolicy Bypass -File .\sim\run_mes50hp_top_image.ps1`

Expected: PASS and preserve the existing result image outputs.

- [x] **Step 2: Run the new adapter, controller and structural tests**

Run each of:

```powershell
.\sim\run_ddr3_pixel_read_adapter.ps1
.\sim\run_board_video_control.ps1
.\sim\run_pgl50h_board_top_compile.ps1
```

Expected: all PASS.

- [x] **Step 3: Write the PDS handoff**

Specify the exact source-add order: HDMI I2C RTL, `wr_fram_buf`, `wr_buf`, `wr_cmd_trans`, `wr_ctrl`, `rd_ctrl`, `wr_rd_ctrl_top`, `DDR3_50H` generated source tree, existing algorithm sources, new board RTL, and `pgl50h_board_top.sv` last. Instruct the user to set `pgl50h_board_top` as Top, replace `clk.fdc` with `constraints/mes50hp/pgl50h_board_top.fdc`, run Compile → Synthesis → Device Map → Timing, and report the first error verbatim if a regenerated IP differs.

- [x] **Step 4: Update the board README**

State that `mes50hp_top` is internal and must never be selected as the PDS physical top after this change.


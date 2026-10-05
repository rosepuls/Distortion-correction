# PGL50H 时序收敛实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or `executing-plans` to implement this plan task-by-task. 每个任务完成后都必须运行对应的仿真或 PDS 检查，并记录结果。

**目标：** 在保持 100 MHz 核心时钟、720p30 吞吐率和图像结果不变的前提下，使 PGL50H 完整 RTL 工程的 setup、hold、recovery 和 removal 时序全部收敛，并具备生成下载文件和上板测试的条件。

**架构：** 先用快速 P&R 工程筛选算法核心和缓存 RTL 的局部修改，再用完整 `pgl50h_rtl_synth` 工程进行唯一正式签核。主要改动分为三条路径：将 Coordinate FIFO 改为同步 RAM/寄存器输出、将 Tile Cache 查询拆成保持一拍吞吐率的流水线、切分畸变核心的径向乘法链；最后单独处理复位 recovery 和小幅 hold 违例。

**技术栈：** SystemVerilog、PGL50H PDS/Fabric Compiler、XSim、PGL DRM/APM 资源、PGL50H FDC 时序约束。

## 全局约束

- 核心算法时钟保持 100 MHz，不通过降低频率规避时序问题。
- 目标模式保持 1280×720@30。
- 720p30 单帧处理周期不超过 `TARGET_BUDGET = 2,500,000`。
- Tile Cache 保持 16 Set × 4 Way、PLRU 配置。
- Coordinate FIFO 保持深度 544，并保留 32 个保护槽。
- 不改变定点位宽、移位位置、饱和规则和图像算法数学结果。
- 不使用覆盖真实数据路径的全局 `false_path` 或 `multicycle_path`。
- 快速 P&R 只用于快速反馈；完整 `pgl50h_rtl_synth` 是最终时序签核依据。
- RTL 修改前后都必须检查像素数量、像素顺序、SOF/EOL 和帧完成协议。

## 当前基线

当前 PDS 报告已经确认存在三类问题：

| 路径 | 当前结果 | 处理方向 |
|---|---:|---|
| 快速工程慢角 setup | WNS −2.493 ns | 切分畸变核心径向乘法/饱和链 |
| 完整工程 `ddrphy_clkin` 慢角 setup | WNS −15.825 ns | 切断 Coordinate FIFO 到 Tile Cache 的组合路径 |
| 完整工程 `ddrphy_clkin` 快角 setup | WNS −8.162 ns | 与慢角路径一起通过 RTL 流水化解决 |
| 完整工程 `ddrphy_clkin` hold | 约 −0.09 ns | setup 稳定后由 PDS hold fix 和局部布局处理 |
| `cfg_clk → video_pixel_clk` recovery | WNS −3.549 ns | 精确约束复位同步器异步复位端 |

关键报告：

- `boards/pgl50h/pds/pgl50h_fast_pr/place_route/pgl50h_fast_pr_top_timing_summary_after_hold_fix.txt`
- `boards/pgl50h/pds/pgl50h_rtl_synth/place_route/pgl50h_board_top_timing_summary_after_hold_fix.txt`
- `boards/pgl50h/pds/pgl50h_rtl_synth/report_timing/pgl50h_board_top.rtr`

---

## 实施进度（2026-10-04）

### 已完成并经 XSim 验证的 RTL 优化

- [x] **Coordinate FIFO：同步存储与寄存器化输出。** 已将坐标、分数和 sideband 打包为 payload，改为 `head_payload` 输出的同步读路径；保留 544 深度、32 个保护槽、非二次幂回绕以及满载时同周期入队/出队。`tb_coordinate_fifo.sv` 已增加 `out_valid && !out_ready` 时 payload 稳定性检查。
- [x] **Pixel Tile Cache：查询/缺失处理流水化。** 已完成固定宽度地址预解码、同步 Bank 读对齐、miss/refill 顺序阻塞、失效期间的重新检查和 Metadata FIFO 容量调整。生产参数的 Bank 地址已改为显式位拼接，避免移位表达式的位宽推断差异。
- [x] **畸变核心：Horner 链切分。** `distortion_core_optimized.sv` 已增加 `stage2k`，把 `k2 × r²` 与 Horner 加法分到相邻周期；数据与全部 sideband 同步延迟，核心端到端延迟由 15 变为 16 周期。
- [x] **功能、吞吐率与整图回归。** FIFO、Cache、缓存引擎、压力测试、畸变核心、板级编译和完整 720p 回归均通过。720p30 为 `921600` 像素、`1.329183 cycles/pixel`（`1,224,975` 核心周期），完整链路输出 `921600` 像素，RGB888 与 golden 逐像素一致。
- [x] **仿真图片资产。** 已由整图回归覆盖 `result/sim_assets/cache_full_chain_1280x720/` 中的 golden、RTL 输出和对比图片。

### 最新完整 PDS 结果与剩余问题

最新一次正式完整工程 `pgl50h_rtl_synth` 报告显示，FIFO/Cache/畸变核心优化已显著改善 setup：

| 类别 | 最新结果 | 状态 |
|---|---:|---|
| `ddrphy_clkin` 慢角 setup | WNS `-1.872 ns`，TNS `-399.607 ns`，456 endpoints | 未收敛 |
| `ddrphy_clkin` 快角 setup | WNS `+1.311 ns` | 通过 |
| 全部 hold | 最低 WHS `+0.100 ns` | 通过 |
| `cfg_clk → video_pixel_clk` recovery | 慢角约 `-4.192 ns`、快角约 `-2.920 ns`，2 endpoints | 未收敛，独立处理 |

当前最差**真实数据**路径来自 `cached_pixel_fetch_engine_inst/meta_count[10]` 到 `bilinear_interp_inst/s1_top_red[8]`，慢角 setup WNS 为 `-2.002 ns`。其组合锥为：Metadata FIFO 的计数/空判断 → `cache_response_fire` 对四路像素的宽数据选择 → 水平双线性差分与 APM 乘法 → Bilinear 第一级寄存器。该路径逻辑和布线延迟均接近一半，优先消除“valid 控制宽数据 mux”，而不改变算法或增加周期。

快速 P&R 曾出现已删除旧信号的解析报错，因此其旧 WNS 不作为本轮判断依据；本文件的正式签核仍以用户运行的完整 `pgl50h_rtl_synth` 为准。

**2026-10-04 16:34 完整 PDS 更新：** Bilinear 入口的 `meta_count → s1_top_*` 路径已不再位于最差真实数据路径中，说明任务 4B 成功切断了该控制锥。当前 timing summary 的慢角 setup 为 WNS `-2.090 ns`、TNS `-323.444 ns`、297 endpoints，快角 setup 为 `+0.989 ns`；但慢角/快角 hold 分别出现 `-0.056 ns`（3 endpoints）与 `-0.100 ns`（13 endpoints），recovery 仍为慢角 `-4.250 ns`、快角 `-2.938 ns`。`pgl50h_board_top.rtr` 的最差真实数据路径已转移到畸变核心：平方 APM、饱和和 `x²+y²` 写入 `stage2_r2_q18`（约 `-2.191 ns`），其次为 `r² × Horner` 后的饱和/加法链（约 `-2.148 ns`）。

---

### 任务 4B：收敛 Bilinear 响应入口的控制 MUX（当前执行）

**目标：** 从 Cache 响应到 Bilinear 第一级寄存器的路径中移除由 `meta_count/cache_response_fire` 驱动的宽数据零填充 MUX。保持 Bilinear 的两级延迟、每周期一个输入/输出的吞吐率、黑边语义及 SOF/EOL 对齐不变。

**文件：**

- 修改：`rtl/platform/common/memory/cached_pixel_fetch_engine.sv`
- 修改：`rtl/algorithm/interpolation/bilinear_interp.sv`
- 验证：`sim/tb_bilinear_interp.sv`、现有缓存/吞吐率/整图回归

- [x] **步骤 1：保留当前 PDS 失败基线。**

  以完整工程的真实数据路径 `meta_count[10] → s1_top_red[8]`、WNS `-2.002 ns` 作为本轮 red timing gate；不将 recovery 违例混入此轮数据路径修改。

- [x] **步骤 2：解除 Cache 响应数据与 valid 的组合绑定。**

  在 `cached_pixel_fetch_engine.sv` 中，将 `p00/p10/p01/p11` 和 Metadata FIFO 的 `fx/fy/sof/eol/coord_valid` 作为原始 payload 送入 Bilinear；只使用 `cache_response_fire` 作为 `in_valid`，并保持 `coord_valid = cache_response_fire && cache_coord_valid && meta_coord_valid[meta_rd_ptr]`。因为响应握手成立必然意味着 Metadata 非空，所以 payload 在无效拍的值属于不可观察状态，不能再由 `meta_count` 控制置零。

- [x] **步骤 3：让 Bilinear 第一级数据寄存器使用 clock-enable 语义。**

  在 `bilinear_interp.sv` 中，仅在 `in_valid` 时更新 `s1_top_*`、`s1_bottom_*` 和 `s1_dy`；删除无效拍向这些宽寄存器写零的 `else` 分支。`s1_valid` 仍每拍更新，第二级仍以 `s1_valid` 决定有效输出或空泡，复位和接口时序保持原语义。

- [x] **步骤 4：运行定向和全链路 XSim 回归。**

  先运行 Bilinear 单元测试与缓存引擎测试，再运行畸变核心、720p30 吞吐率、板级编译和 `run_mes50hp_top_cache_image_720p.ps1`。整图必须再次覆盖 `result/sim_assets/cache_full_chain_1280x720/`，并满足 `921600` 像素、预算内周期和逐像素一致。

  已完成：`TEST_PASS: bilinear_interp`、`TEST_PASS: cached_pixel_fetch_engine`、畸变核心 golden 与 stream（`latency=16`）、`TEST_PASS: 720p30_throughput`（`1,224,975` cycles）、`TEST_PASS: pgl50h_board_top_compile`，以及整图 `outputs=921600 commands=82716 beats=330864 cycles=1959088`。目标图片已于 15:56 重新生成。

- [x] **步骤 5：由用户运行正式完整 PDS。**

  重点检查 `meta_count → bilinear s1_*` 路径是否消失或明显缩短、慢角 setup WNS/TNS 是否改善，确认 hold 不回退。该步由用户在 PDS 中执行，本代理只分析报告。

  已确认：Bilinear 路径不再是最差路径；总体 setup 尚未收敛，且本轮完整 PDS 出现新的轻微 hold 违例。因此后续 RTL 改动继续针对报告中的畸变核心数据锥，hold 在 setup 主路径稳定后统一处理。

**历史后备方案：** 在 Bilinear 前增加 S0 响应寄存器曾作为入口路径的后备方案；当前报告已转移到 Bilinear 纵向计算，因此该方案暂不实施，避免无必要地增加 Cache 到插值入口的额外延迟。

---

### 任务 4C：切断平方结果到半径求和的组合链（当前执行）

**根因：** `stage1_x_q18 × stage1_x_q18` 的 APM 输出要在同一周期经过 Q18 饱和、`x²+y²` 加法和第二次饱和，才写入 `stage2_r2_q18`。完整 PDS 报告显示该锥有 13 个逻辑级，慢角约 `-2.191 ns`。

**文件：**

- 修改：`rtl/algorithm/distortion/distortion_core_optimized.sv`
- 修改：`sim/tb_distortion_core_optimized.sv`
- 修改：`sim/tb_distortion_core_optimized_stream.sv`

- [x] **步骤 1：建立 17 周期的失败测试。**

  将 golden-vector 与连续流 testbench 的固定延迟从 16 调整为 17。未修改 RTL 时，25 组 golden vector 均在第 16 周期提前出现，测试按预期失败。

- [x] **步骤 2：增加 Stage 2S 平方结果寄存级。**

  `stage2s_*` 保存 `x²/y²/xy` 的原有 Q18 饱和结果和全部数据/控制 sideband；下一拍的 `stage2_*` 只完成原有 `x²+y²` 相加与饱和。该级使用 `syn_preserve`，防止综合重新跨越该边界合并乘法和加法。

- [x] **步骤 3：验证核心数学和延迟。**

  XSim golden-vector 25 组通过；连续流测试通过并报告 `latency=17 checked=7`。

- [ ] **步骤 4：运行全链路回归并由用户执行完整 PDS。**

  运行 720p30、板级编译与 1280×720 整图回归，重新覆盖图片资产；再检查平方路径是否消失、`r² × Horner` 是否成为下一最差路径，以及 hold/recovery 的变化。

  已完成仿真部分：720p30 仍为 `921600` 像素、`1,224,975` 周期、`1.329183 cycles/pixel`；`pgl50h_board_top_compile` 通过；整图回归为 `outputs=921600 commands=82716 beats=330864 cycles=1959088`，并已重新覆盖 `result/sim_assets/cache_full_chain_1280x720/`。待用户运行完整 PDS 后再完成本步骤。

**后备方案（只在任务 4C 验证后再决定）：** 若 `r² × Horner → radial_q18` 成为剩余最差路径，则单独插入 `radial_delta_q18` 寄存级，把第二个径向 APM 乘法与 `1 + radial_delta` 饱和加法分离；同样先把固定延迟测试加一拍并验证失败，再改 RTL。不要与任务 4C 合并实施。

---

### 任务 4D：切断 Bilinear 纵向乘法到 RGB 输出的组合链（当前执行）

**根因：** 任务 4B 后，完整 PDS 的最差数据路径转移到 `bilinear_interp_inst/s1_top_red → out_pixel`，慢角约 `-2.993 ns`。该路径在同一周期完成纵向差分、`difference × dy`、Q32 求和、算术右移和 RGB 饱和。

**文件：**

- 修改：`rtl/algorithm/interpolation/bilinear_interp.sv`
- 修改：`sim/tb_bilinear_interp.sv`
- 验证：缓存引擎、720p30、板级编译和整图回归

- [x] **步骤 1：建立 3 周期失败测试。**

  先将 Bilinear testbench 延迟改为 3 周期；旧两级 RTL 提前输出，测试报告了提前输出失败。

- [x] **步骤 2：增加纵向乘积寄存级。**

  新增 `vertical_product_q32`，第二级只计算纵向差分乘法并寄存 `top_q16`、乘积和全部 valid/sideband；第三级执行原有 Q32 求和、右移和饱和，保持定点数学结果不变。

- [x] **步骤 3：修正单元测试输入协议。**

  将单元测试改为单周期 `in_valid` 脉冲，避免等待输出期间重复注入相同事务；验证 3 周期延迟、空泡、无效坐标和 SOF/EOL。

- [x] **步骤 4：运行 XSim 全链路回归。**

  `bilinear_interp`、`cached_pixel_fetch_engine` 和板级编译均通过；720p30 为 `921600` 像素、`1,224,976` 周期、`1.329184 cycles/pixel`；整图为 `921600` 输出像素、`82716` 命令、`330864` beat、`1959089` 周期，RGB888 逐像素一致。目标图片已重新覆盖。

- [ ] **步骤 5：由用户运行完整 PDS。**

  重点检查 `s1_top_* → out_pixel` 路径是否消失，慢角 setup 是否转正，并确认新增输出级没有扩大 hold 违例。若仍有 setup 违例，再单独决定是否把纵向差分与乘法继续拆开；不与 recovery 修复合并。

---

### 任务 4E：切断径向乘积到径向缩放因子的组合链

**根因：** 任务 4C 后，平方路径已不再是最差真实数据路径；完整 PDS 的最差路径转移到 `stage2h_horner_t_q18 → radial_product → radial_delta_q18 → radial_sum_q18 → radial_q18`。该路径在同一周期完成第二次径向乘法、Q18 右移/饱和、`1.0 + delta` 和再次饱和，慢角 setup 约 `-3.680 ns`。

**文件：**

- 修改：`rtl/algorithm/distortion/distortion_core_optimized.sv`
- 修改：`sim/tb_distortion_core_optimized.sv`
- 修改：`sim/tb_distortion_core_optimized_stream.sv`
- 验证：`sim/run_distortion_core_optimized.ps1`、`sim/run_720p30_throughput.ps1`、`sim/run_pgl50h_board_top_compile.ps1`、`sim/run_mes50hp_top_cache_image_720p.ps1`

- [x] **步骤 1：建立 18 周期的失败测试。**

  先把 golden-vector 与连续流 testbench 的固定延迟从 17 调整为 18；未修改 RTL 时，旧实现提前一个周期输出，核心回归按预期失败，形成 RED 门禁。

- [x] **步骤 2：增加 Stage 3D 径向 delta 寄存级。**

  新增 `stage3d_radial_delta_q18`，并寄存其对应的坐标平方、交叉项、Horner 中间量、映射参数和 SOF/EOL sideband。下一拍的 Stage 3 只完成 `1.0 + delta` 与径向饱和，避免综合器把第二次 APM 乘法、量化饱和和加法重新跨级合并；valid/sideband 与 payload 同步推进。

- [x] **步骤 3：完成 XSim 回归并重新生成图像资产。**

  核心黄金向量 `25/25` 通过；流式回归通过并报告 `latency=18 checked=7`；720p30 仍为 `921600` 像素、`1,224,976` 周期、`1.329184 cycles/pixel`；PGL50H 板级顶层编译通过；完整 1280×720 链路输出 `921600` 像素、`82716` 命令、`330864` beat、`1959089` 周期，RGB888 与 golden frame 逐像素一致。`result/sim_assets/cache_full_chain_1280x720/` 已重新覆盖生成。

- [x] **步骤 4：由用户运行完整 PDS。**

  重点检查 `stage2h_horner_t_q18 → radial_product/radial_q18` 路径是否消失或明显缩短，慢角 setup WNS/TNS 是否改善，并确认 fast/slow hold、recovery 没有回退。本轮不修改约束，也不以布局 seed 掩盖 RTL 结构性路径。

  **2026-10-04 18:37 完整 PDS 结果：** 慢角 setup 从上一轮的 `WNS=-3.603 ns / TNS=-253.283 ns / 214 endpoints` 改善为 `WNS=-0.674 ns / TNS=-14.326 ns / 40 endpoints`；快角 setup 为 `WNS=+2.190 ns`、无违例。慢角 hold 为 `WHS=+0.055 ns`、无违例；快角 hold 仅剩 `WHS=-0.003 ns`、1 个 endpoint。径向路径已从最差路径移走，详细报告中的当前 setup 瓶颈转为 `ddrphy_clkin` 域的 Cache 控制路径 `s2_recheck_pending → s2_missing_tile_y`。Recovery 仍是 `cfg_clk → video_pixel_clk`，慢角 `-4.183 ns`、快角 `-2.891 ns`，需要后续单独处理复位同步释放。

---

### 任务 4F：拆分第二径向乘法与 Q18 delta 量化（当前执行）

**根因：** Recovery 约束收敛后，最新正式完整工程仅剩 `ddrphy_clkin` 慢角 setup
违例，timing summary 为 WNS `-0.312 ns`、TNS `-3.868 ns`、20 endpoints。详细
`pgl50h_board_top.rtr` 的代表路径为
`stage2h_horner_t_q18[13] → radial_product → stage3d_radial_delta_q18[10]`，到达时间
`20.550 ns`、要求时间 `20.174 ns`、slack `-0.376 ns`；APM 乘法和后续右移/饱和加法链仍在
同一 100 MHz 周期中。这里的 `ddrphy_clkin` 是该算法逻辑所用时钟域名称，并非 DDR PHY IP
内部路径。

**文件：**

- 修改：`rtl/algorithm/distortion/distortion_core_optimized.sv`
- 修改：`sim/tb_distortion_core_optimized.sv`
- 修改：`sim/tb_distortion_core_optimized_stream.sv`
- 验证：`sim/run_distortion_core_optimized.ps1`、`sim/run_720p30_throughput.ps1`、`sim/run_pgl50h_board_top_compile.ps1`、`sim/run_mes50hp_top_cache_image_720p.ps1`

- [x] **步骤 1：建立 19 周期 RED 门禁。**

  先将 golden-vector 与连续流 testbench 的固定延迟从 18 调整为 19；未修改 RTL 时，
  25 组黄金向量在检查拍为空，按预期全部提前一拍失败。

- [x] **步骤 2：增加 Stage 3P 全精度径向乘积寄存级。**

  `stage3p_radial_product` 以原有 `41` 位有符号乘积位宽保存 `r² × Horner`，同时延迟全部
  后续所需坐标、畸变参数与 SOF/EOL/valid sideband。`stage3d` 改为只对已寄存乘积完成原有
  `>>> 18` 与 `saturate_s21`，`stage3` 仍只完成原有 `1.0 + delta` 与饱和。所有新边界均带
  `syn_preserve`，防止 PDS 跨越该边界重新合并。

- [x] **步骤 3：完成核心 XSim GREEN 回归。**

  `run_distortion_core_optimized.ps1` 已通过：黄金向量 `25/25` 通过；连续流通过并报告
  `latency=19 checked=7`。定点输出、空泡、SOF/EOL 和配置切换检查均保持通过。

- [ ] **步骤 4：完成全链路回归，等待用户执行正式完整 PDS。**

  已完成仿真：720p30 为 `921600` 像素、`1,224,976` 周期、`1.329184 cycles/pixel`；
  `pgl50h_board_top_compile` 通过；完整 1280×720 链路为 `921600` 输出像素、`82716` 命令、
  `330864` beat、`1,959,089` 周期，RGB888 与黄金帧逐像素一致。
  `result/sim_assets/cache_full_chain_1280x720/` 已于 22:05 重新覆盖生成。

  用户随后运行 `pgl50h_rtl_synth`，重点确认
  `stage2h_horner_t_q18 → stage3d_radial_delta_q18` 路径消失，慢角 setup 转正或显著改善，且
  setup/hold/recovery/removal 其他类别不回退。

---

### 任务 4G：切断 Bilinear 垂直差分到 APM 乘法的组合链（当前执行）

**根因：** 任务 4F 后，最新完整 PDS 的最差真实数据路径已转移到
`bilinear_interp_inst/N69 → N177_m2`：`s1_bottom_green` 输出先经过 17 位垂直差分进位链，
随后直接进入 `vertical_product_q32` 的 APM 乘法，慢角详细路径 slack 为 `-0.261 ns`。

**文件：**

- 修改：`rtl/algorithm/interpolation/bilinear_interp.sv`
- 修改：`sim/tb_bilinear_interp.sv`
- 验证：缓存引擎、缓存吞吐率、缓存压力、畸变核心、720p30、板级编译和整图回归

- [x] **步骤 1：建立 4 拍 RED 门禁。**

  将 Bilinear 单元测试固定延迟从 3 拍调整为 4 拍；旧 RTL 提前一拍输出，测试按预期失败。

- [x] **步骤 2：增加 s2d 垂直差分寄存级。**

  新增 `s2d_vertical_difference_{red,green,blue}`、对应 top 项、dy 和全部 sideband 寄存器。
  原有 `s2` 现在只完成已寄存差分与 dy 的 APM 乘法，最终级继续执行原有 Q32 求和、移位和
  饱和。新增边界使用 `syn_preserve`，不改变定点位宽和数学顺序。

- [x] **步骤 3：完成 XSim 全链路回归。**

  Bilinear 单元、缓存引擎、缓存吞吐率、缓存压力、畸变核心黄金/流式、720p30 和板级编译
  均通过。720p30 为 `921600` 像素、`1,224,977` 周期、`1.329185 cycles/pixel`；完整
  1280×720 链路为 `921600` 输出像素、`82716` 命令、`330864` beat、`1,959,090` 周期，
  RGB888 与黄金帧逐像素一致，图片资产已重新覆盖。

- [ ] **步骤 4：由用户运行完整 PDS。**

  检查 `s1_bottom_* → vertical_product_q32` 路径是否消失，慢角 setup 是否转正，同时确认
  hold、recovery、removal 和快角 setup 不回退。

---

### 任务 1：建立时序优化前的回归门禁

**文件：**

- 检查：`sim/tb_coordinate_fifo.sv`
- 检查：`sim/tb_pixel_tile_cache.sv`
- 检查：`sim/tb_cached_pixel_fetch_stress.sv`
- 检查：`sim/tb_720p30_throughput.sv`
- 检查：`sim/run_720p30_throughput.ps1`
- 检查：`sim/run_mes50hp_top_cache_image_720p.ps1`

**接口要求：**

- 所有现有模块接口保持兼容。
- 每次改动都必须能重新运行单元测试、压力测试、整图测试和吞吐率测试。
- `tb_720p30_throughput.sv` 中的 `TARGET_BUDGET = 2500000` 不得删除或放宽。

- [ ] **步骤 1：确认当前基线测试全部通过。**

  运行 FIFO、Tile Cache、缓存压力、720p30 吞吐率和 720p 图像测试，记录每个测试的 `TEST_PASS`、输出像素数、帧周期数和 DDR 命令数。

- [ ] **步骤 2：补充 FIFO 输出稳定性检查。**

  在 `out_valid && !out_ready` 期间锁存并比较完整 payload，确保 `x0/y0/fx/fy/coord_valid/sof/eol` 不发生变化。

- [ ] **步骤 3：补充 Cache 请求顺序检查。**

  对连续 hit、单个 miss、连续 miss、DDR 回压和 refill 完成后的首个 hit 分别检查响应顺序，确认后续请求不会越过未完成的 miss。

- [ ] **步骤 4：保存未修改基线。**

  将当前快速工程和完整工程的 timing summary、最差路径、资源报告复制到独立的基线记录目录或提交记录中。基线只读保存，不覆盖原始报告。

**验收：** 所有现有测试通过，并且拥有可比较的时序、资源和吞吐率基线。

---

### 任务 2：将 Coordinate FIFO 改为同步存储和寄存器输出

**文件：**

- 修改：`rtl/platform/common/memory/coordinate_fifo.sv`
- 必要时新增：`rtl/platform/common/memory/coordinate_fifo_ram.sv`
- 必要时新增：`rtl/vendor/pgl50h/memory/pgl50h_coordinate_fifo_ram.v`
- 必要时新增：`sim/pgl50h_coordinate_fifo_ram_model.sv`
- 测试：`sim/tb_coordinate_fifo.sv`

**接口要求：**

- 对外保持 `coordinate_fifo` 现有端口和握手语义。
- payload 必须包含两个坐标、两个 16 bit 小数部分以及 `coord_valid/sof/eol`。
- 当前 `COORD_WIDTH=13`、`FRAC_WIDTH=16` 时，打包 payload 宽度为 61 bit。
- 支持每周期一次入队和一次出队。

- [ ] **步骤 1：定义打包 payload。**

  将 `x0_mem/y0_mem/fx_mem/fy_mem/coord_valid_mem/sof_mem/eol_mem` 合并为一个定宽 payload，统一写入存储阵列。

- [ ] **步骤 2：实现同步读 RAM。**

  用同步读模板替换 `assign out_x0 = x0_mem[read_ptr]` 一类的组合读。读数据必须先进入 `head_payload`，不能再次由 `read_ptr` 直接驱动 Cache。

- [ ] **步骤 3：加入弹性输出寄存器或两级预取。**

  设计 `head_valid/head_payload`，必要时增加 `next_valid/next_payload`，保证同步 RAM 延迟不会造成连续输出空泡。`out_valid && !out_ready` 时保持 head payload 不变。

- [ ] **步骤 4：保持 FIFO 边界语义。**

  保留深度 544、保护槽 32、非 2 的幂指针回绕、满时同周期出入队和复位行为。不要将深度改为 512。

- [ ] **步骤 5：确认 PGL DRM 推断。**

  先使用可综合同步 RAM 模板；如果 PDS 仍映射为大量 LUTRAM，再按现有 Tile Cache Bank 的包装模式增加 PGL 专用 RAM wrapper 和仿真模型。

- [ ] **步骤 6：运行 FIFO 和解耦流水测试。**

  检查顺序、回压、同时入出队、回绕、保护槽和输出稳定性。

**验收：** FIFO 相关测试通过；PDS 资源报告显示 FIFO 存储主要进入 DRM；原先 `read_ptr → x0_mem/y0_mem → Tile Cache` 的组合路径被寄存器或同步 RAM 切断；连续坐标输出没有空泡。

---

### 任务 3：将 Pixel Tile Cache 查询拆成流水线

**文件：**

- 修改：`rtl/platform/common/memory/pixel_tile_cache.sv`
- 修改：`rtl/platform/common/memory/cached_pixel_fetch_engine.sv`
- 测试：`sim/tb_pixel_tile_cache.sv`
- 测试：`sim/tb_pixel_tile_cache_packed.sv`
- 测试：`sim/tb_cached_pixel_fetch_engine.sv`
- 测试：`sim/tb_cached_pixel_fetch_stress.sv`

**接口要求：**

- `lookup_valid/lookup_ready`、`lookup_rsp_valid/lookup_rsp_ready` 和 refill 接口保持语义兼容。
- 连续命中情况下，流水线填满后仍然支持每周期一个 lookup。
- miss 必须阻塞后续请求，不能发生响应乱序。
- Bank RAM 的同步读延迟必须和响应 Token 严格匹配。

- [ ] **步骤 1：增加 S0 请求寄存级。**

  在接受 `lookup_valid && lookup_ready` 时锁存 `lookup_x0/lookup_y0` 和请求有效标志，切断 FIFO 输出到 Cache 地址解析的组合路径。

- [ ] **步骤 2：增加 S1 地址预解码级。**

  对四个邻域寄存并生成定宽的 `tile_x/tile_y/set/bank/slot`，所有地址结果进入寄存器。

- [ ] **步骤 3：增加 S2 Tag 查询级。**

  完成 valid/tag 比较，并寄存 `req_hit`、`req_way`、`req_all_hit`、`missing_tile` 和 `missing_set`。Tag 查询使用固定宽度信号，不让 `integer` 进入实际数据通路。

- [ ] **步骤 4：把 victim 选择限制到 miss。**

  使用显式 `missing_found` 标志，不再用 Tile 坐标 `(0,0)` 作为“未找到”的哨兵。只有 `req_coord_valid && !req_all_hit` 时才执行 invalid Way、PLRU 或 LRU 选择；命中路径不得经过 victim 选择逻辑。

- [ ] **步骤 5：增加 S3 请求处理级。**

  hit 请求发起四个 Bank 读；边界无效请求生成黑色响应；miss 请求锁存 refill 描述符和 victim 信息，并进入单独的 refill 状态机。

- [ ] **步骤 6：处理 miss 阻塞和流水排空。**

  miss 出现后停止接受更年轻的 lookup，保证 miss 前的 hit 已按顺序发出，miss 后的请求不会越过 refill。refill 完成后重新检查原请求，再恢复 lookup。

- [ ] **步骤 7：对齐同步 Bank 响应。**

  将 `bank/slot/way/coord_valid` 与 Bank RAM 的读延迟一起打入流水寄存器，使 `pixel_p00/p10/p01/p11`、`cache_hit` 和响应 valid 同拍到达。

- [ ] **步骤 8：检查 Metadata FIFO 容量。**

  在新增 Cache 流水延迟后检查 `cached_pixel_fetch_engine` 的 Metadata FIFO 不溢出、不下溢，并保持 `fx/fy/SOF/EOL` 与 Cache 响应对应。

**验收：** Tile Cache 单元、打包 Cache、缓存引擎和压力测试全部通过；连续 hit 无空泡；miss/refill 顺序正确；完整 PDS 中不再出现 FIFO 读指针直接驱动 Cache Tag/valid 选择的长路径。

---

### 任务 4：切分畸变核心径向计算路径

**文件：**

- 修改：`rtl/algorithm/distortion/distortion_core_optimized.sv`
- 测试：现有畸变核心测试和整图测试
- P&R：`boards/pgl50h/pds/pgl50h_fast_pr`

**接口要求：**

- 保持畸变核心的输入输出接口不变。
- 不改变定点数学表达式的位宽、右移和饱和位置。
- 所有 `valid/sof/eol` 和坐标配置 sideband 必须与数据增加同样的流水延迟。

- [ ] **步骤 1：确认当前长路径。**

  重点检查 `stage2h_horner_t_q18 → radial_product → radial_delta_q18 → radial_q18 → radial_x_product/radial_y_product` 链路。

- [ ] **步骤 2：在径向乘法与加法之间插入一级寄存器。**

  将 `radial_delta_q18` 和所需 sideband 先写入新的 `stage2r` 寄存器；下一拍再执行 `1.0 + radial_delta_q18` 和饱和得到 `stage3_radial_q18`。

- [ ] **步骤 3：同步延迟所有旁路字段。**

  同步延迟 `valid`、`sof`、`eol`、`x/y`、`x²/y²/xy/r²`、`p1/p2`、`fx/fy/cx/cy`，避免数学值和标志错位。

- [ ] **步骤 4：运行数学和图像回归。**

  对比优化前后的坐标、边界黑色像素、整图 golden 和输出标志。

- [ ] **步骤 5：运行快速 P&R。**

  快速工程目标为慢角 setup WNS ≥ +1.0 ns、快角 setup WNS ≥ 0、hold WHS ≥ 0。若仍失败，继续从报告中处理下一条实际长路径，不直接降低时钟。

**验收：** 畸变核心结果逐点一致，吞吐率没有下降，快速工程达到带余量的时序通过。

---

### 任务 5：运行第一次完整 P&R 并按路径分类

**文件：**

- 工程：`boards/pgl50h/pds/pgl50h_rtl_synth`
- 约束：`boards/pgl50h/constraints/pgl50h_board_top.fdc`
- 报告：`boards/pgl50h/pds/pgl50h_rtl_synth/place_route/`
- 报告：`boards/pgl50h/pds/pgl50h_rtl_synth/report_timing/`

- [ ] **步骤 1：执行完整工程的 Compile、Synthesis、Device Map、Place & Route 和 Report Timing。**

- [ ] **步骤 2：分别读取慢角和快角 setup/hold。**

- [ ] **步骤 3：读取 recovery/removal、未约束路径、时钟利用率和资源利用率。**

- [ ] **步骤 4：导出最差 20 条路径。**

  按以下类别归类：FIFO/Cache、畸变核心、DDR 控制器、复位、跨时钟、IO 和高扇出网络。

- [ ] **步骤 5：决定下一轮处理方式。**

  WNS 小于 −1 ns 时继续做 RTL 结构修改；接近 0 ns 时再检查寄存器复制、局部布局、扇出和 PDS seed。不能用布局种子掩盖结构性长路径。

**验收：** 得到一份更新后的完整工程报告，并确认剩余违例属于复位 recovery、hold 或局部路径，而不是原始 FIFO/Cache 长路径。

---

### 任务 6：处理视频复位同步器 recovery 违例

**文件：**

- 修改：`rtl/board/pgl50h/clock_reset.sv`
- 检查：`rtl/board/pgl50h/pgl50h_board_top.sv`
- 修改：`boards/pgl50h/constraints/pgl50h_board_top.fdc`
- 检查：`boards/pgl50h/pds/pgl50h_rtl_synth/constraint_check/`

- [x] **步骤 1：确认 recovery 违例的起点和终点。**

  基线违例确认来自 `cfg_clk` 产生的 `rstn_out` 到
  `video_reset_sync/reset_release` 两级同步器的异步复位引脚；当前实现通过视频域同步采样
  消除这条异步 `RS` 路径，而不是在 FDC 中引用尚未生成的内部 pin 对象。

- [x] **步骤 2：调整视频域复位结构。**

  输入域和核心域仍保留原有异步断言、同步释放结构；视频域改为在
  `video_pixel_clk` 内同步采样 `rstn_out`，并保留两级本地释放。这样不再把
  `cfg_clk` 的复位释放直接接到视频同步器触发器的异步 `RS` 引脚。

- [x] **步骤 3：增加 PDS 支持的同步器属性。**

  确保两级复位同步触发器不会被优化、合并或跨级重定时，并尽量靠近放置。

- [x] **步骤 4：改用可导入的时钟对象级 CDC 约束。**

  曾尝试用 `get_pins -hierarchical -regexp` 精确匹配两个 `RS` 引脚，但 PDS
  在 FDC 导入阶段报告 `Nothing matched for 'to_list'`，说明综合网表内部 pin
  尚未成为可解析约束对象。当前改为对 `cfg_clk → video_pixel_clk` 添加一条
  时钟对象级 CDC 例外，并由 timing-report 审计确保该方向只包含视频复位同步器。

- [ ] **步骤 5：运行约束检查和完整 P&R。**

  确认 recovery 违例消失，同时正常数据路径仍然被时序分析；约束检查不能增加 error。

**2026-10-04 实现记录：** 首版 `set_false_path -to [get_pins ...]` 已被用户的 PDS
编译日志否决，错误为 `CommandTiming-0057: Nothing matched for 'to_list'`，因此已从
`pgl50h_board_top.fdc` 删除。当前在 `clock_reset.sv` 增加
`mes50hp_reset_sync_sync_only`，其视频域 `reset_release` 只在
`video_pixel_clk` 上更新，并保留 `syn_preserve`；`pgl50h_board_top.sv` 的
`video_reset_sync` 已切换到该模块。随后在 FDC 中加入
`set_false_path -from [get_clocks {cfg_clk}] -to [get_clocks {video_pixel_clk}]`，并在
`check_video_reset_recovery_constraints.ps1` 中增加唯一性和 endpoint 审计：当前 PDS 报告中该
时钟对只有两个复位同步器 endpoint。静态门禁、板级约束一致性检查和
`tb_pgl50h_board_top_compile` XSim 均已通过。步骤 5 仍需用户运行完整 PDS，确认约束导入无误、
`cfg_clk → video_pixel_clk` setup/recovery 不再产生违例，并确认没有普通数据路径被切断。

**验收：** `cfg_clk → video_pixel_clk` recovery WNS ≥ 0，且没有因全局 false path 导致有效路径数量异常减少。

---

### 任务 7：处理剩余 hold 和物理实现问题

**文件：**

- 工程：`boards/pgl50h/pds/pgl50h_rtl_synth`
- 重点报告：`place_route/*timing_summary*`、`report_timing/pgl50h_board_top.rtr`

- [x] **步骤 1：在 setup 稳定后重新执行 PDS hold fix。**

  已重复执行完整 P&R。PDS 路由器每次均运行自动 hold fix；不能将仅重新运行
  `report_timing` 视为新的 P&R 结果。

- [x] **步骤 2：定位最差 hold 路径的起点、终点和时钟偏斜。**

  最新完整报告（2026-10-04 23:32）只有快速角 `ddrphy_clkin` 的两条 hold
  端点：

  - `stage4_cx_q12[6] -> stage5_cx_q12[6]`，WHS `-0.004 ns`，零逻辑级；
  - `pending_tile_x[4] -> tag_x_mem_3_1_4/WD`，WHS `-0.002 ns`，零逻辑级。

  这比此前单条 `pending_tile_x[1] -> tag_x_mem.../WD` 的 `-0.022 ns` 总负裕量
  更好（TNS 从 `-0.022 ns` 降至 `-0.006 ns`），但还不能签核。当前慢角 setup
  WNS 为 `+0.096 ns`，仍通过但余量较小。

- [ ] **步骤 3：优先使用工具支持的 hold 修复和局部布局。**

- [ ] **步骤 4：若下一次 P&R 仍有 Tile Cache tag 写入 hold，则单独处理
  `pending_tile_x -> tag_x_mem/WD`。**

  不得插入寄存器；它会改变 tag 与填充数据的同周期关联。应先使用 PDS 支持的
  局部物理 hold 修复，随后执行 cache/整图回归。

- [ ] **步骤 5：每次 hold 修复后重新检查 setup。**

**验收：** 慢角和快角 hold WHS 均非负，且 setup 没有回退到负值。

---

### 任务 8：完整回归、约束审计和下载文件签核

**文件：**

- 检查：`boards/pgl50h/constraints/pgl50h_board_top.fdc`
- 检查：`sim/run_720p30_throughput.ps1`
- 检查：`sim/run_mes50hp_top_cache_image_720p.ps1`
- 检查：`sim/run_pgl50h_board_top_compile.ps1`
- 生成：完整 PDS 下载文件及最终 timing/resource 报告

- [ ] **步骤 1：运行全部 FIFO、Cache、DDR adapter、压力、整图和吞吐率仿真。**

- [ ] **步骤 2：确认 720p30 一帧周期不超过 2,500,000。**

- [ ] **步骤 3：确认输入输出像素均为 921,600，图像与 golden 逐像素一致。**

- [ ] **步骤 4：审计所有时钟。**

  至少包括 `sys_clk`、`pixclk_in`、`video_pixel_clk`、`cfg_clk`、`ddrphy_clkin`、`ioclk0` 和 `ioclk1`。

- [ ] **步骤 5：审计所有时序类别。**

  setup、hold、recovery、removal 和 minimum pulse width 均必须没有违例。

- [ ] **步骤 6：审计未约束路径和约束警告。**

  不能以“工具没有分析到”为通过依据。重复管脚约束、无效对象和未约束输入必须清理或明确说明原因。

- [ ] **步骤 7：确认资源和物理实现。**

  确认 FIFO/Cache 存储映射符合预期，LUT、FF、DRM、APM、全局时钟和布线资源没有接近不可控的极限。

---

### 任务 9：修复真实 PLL 相位下的 DDR 复位 recovery 与 Cache 重查路径

**根因：** 37.125 MHz PLL 配置的真实 `cfg_clk` 为 9.9593 MHz（`50 MHz × 49 / 246`），不再与
`sys_clk` 整周期对齐。上一版将 `rstn_out` 接入异步断言的 `ddr_reset_sync` 后，正式 PDS 表明
recovery 端点只是迁移为 `ddr_reset_sync/reset_release[*]/RS`，并未消失；根因是 cfg 域信号仍驱动
异步 RS 引脚。慢角 setup 的真实主路径也不是仅 refill 重查，而是正常查询
`s1_set → 四路 Tag 比较/首个缺失选择 → s2_missing_*`。

**文件：**

- 修改：`rtl/board/pgl50h/pgl50h_board_top.sv`
- 修改：`sim/tb_pgl50h_board_top_compile.sv`
- 修改：`sim/check_video_reset_recovery_constraints.ps1`
- 修改：`rtl/platform/common/memory/pixel_tile_cache.sv`
- 修改：`sim/tb_pixel_tile_cache.sv`
- 验证：`sim/run_pgl50h_board_top_compile.ps1`、`sim/run_pixel_tile_cache.ps1`、
  `sim/run_720p30_throughput.ps1`、`sim/run_mes50hp_top_cache_image_720p.ps1`

- [x] **步骤 1：为 DDR 复位写 RED 检查。**

  板级编译 testbench 与静态检查必须要求存在 `ddr_reset_sync`，其时钟为 `sys_clk`，输入为
  `rstn_out`，输出唯一连接到 `DDR3_50H.resetn`；复位释放在 `rstn_out` 后经过两个本地
  `sys_clk` 边沿。旧的直连实现必须使该检查失败。

- [x] **步骤 2：在 sys_clk 域以无 RS 的同步释放 DDR 外部复位。**

  使用 `mes50hp_reset_sync_sync_only` 生成 `ddr_reset_n`，连接到 `DDR3_50H.resetn`。该两级
  `sys_clk` 移位寄存器只使用时钟触发器的 D 输入，不让 `rstn_out` 驱动任何 RS 引脚；不得对
  `cfg_clk → sys_clk` 添加 false path。

- [x] **步骤 3：为 Cache refill 重查写 RED 测试。**

  `tb_pixel_tile_cache.sv` 必须证明：一次 refill 完成后，原请求仅在额外一拍重查后才允许进入
  fill/hit 响应；请求顺序、像素内容、失效期间重查和连续命中吞吐率保持不变。旧实现因重查结果
  在 refill 完成后的第一拍即生效而失败。

- [x] **步骤 4：将正常 Tag 查询与摘要选择拆成相邻寄存级，并统一重查陈旧结果。**

  正常路径改为 `S0 → S1 地址 → S1 Tag(仅四路比较) → S2(全命中/首个缺失摘要)`，使 PDS 的
  Tag 比较和首缺失选择跨寄存器边界。refill/失效更新 Tag 后，若 S1 Tag 中仍有在途请求，必须等其
  进入 S2 后复用 retry 流水重新探测，禁止消费旧 hit/miss 位或发起重复 refill。

- [x] **步骤 5：运行 XSim 回归。**

  DDR reset 静态检查先在旧 RTL 上按预期失败；实现后，`check_video_reset_recovery_constraints.ps1`
  与板级 XSim 均通过，并确认两拍 `sys_clk` 后才释放 `ddr_reset_n`。正常 Tag 级的第三个静默周期
  检查、失效期间重查、以及“共享同一 Tile 的较年轻请求”测试均先在旧 RTL 上失败；实现后 Tile
  Cache、缓存引擎、压力与吞吐率测试均通过。完整图像回归为 `921600` 输出像素、`82716` 命令、
  `330864` beat、`2,228,901` 周期，低于 `3,333,333` 周期预算，RGB888 与 golden 逐像素一致。
  `result/sim_assets/cache_full_chain_1280x720/` 已重新覆盖。

- [ ] **步骤 6：由用户运行正式完整 PDS。**

  正式 PDS 必须确认：`cfg_clk → sys_clk` recovery WNS 非负，且不再出现任何
  `ddr_reset_sync/*/RS` endpoint；`s1_set → tag probe → s2_missing_*` 已不再是单周期临界组合链；并复核 slow/fast
  setup、hold、recovery、removal。

  **2026-10-05 复核与约束更新：** 最新 PDS 的 recovery 已全部通过，Cache/算法
  `ddrphy_clkin` slow setup 已为 `+0.097 ns`；仅剩两条 `cfg_clk → sys_clk` setup 路径，均以
  `ddr_reset_sync/reset_release[*]/RS` 为终点（slow WNS `-3.096 ns`）。这证明 PDS 将 sync-only
  RTL 映射为器件 RS 端口，而非存在普通跨域数据。已在 FDC 添加唯一的
  `set_false_path -from [get_clocks {cfg_clk}] -to [get_clocks {sys_clk}]`，并把静态审计限制为只允许
  这两个 DDR 复位 endpoint；不能用于任何其他 `cfg_clk → sys_clk` 信号。待用户重新运行完整 PDS 验证。

### 任务 10：生成下载文件并保存最终签核报告

- [ ] **步骤 1：生成下载文件并保存最终签核报告。**

  只有仿真、吞吐率、资源、完整 PDS 时序和下载文件都通过后，才进入上板测试阶段。

**最终签核标准：**

```text
功能仿真通过
AND 720p30 图像逐像素一致
AND 720p30 <= 2,500,000 核心周期
AND 所有时钟 setup WNS >= 0
AND 所有时钟 hold WHS >= 0
AND recovery/removal >= 0
AND 无未约束关键路径
AND 资源与 DRM/APM 映射正常
AND 下载文件成功生成
```

只有满足以上全部条件，才能把“时序优化完成”作为真实完成，并进入 PGL50H 上板联调。

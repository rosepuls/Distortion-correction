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

- [ ] **步骤 1：确认 recovery 违例的起点和终点。**

  只针对 `cfg_clk` 产生的 `rstn_out` 到 `video_reset_sync/reset_release` 两级同步器的异步复位引脚进行处理。

- [ ] **步骤 2：保留异步断言、同步释放结构。**

  不把整个视频时钟域声明为异步，也不删除两级 reset synchronizer。

- [ ] **步骤 3：增加 PDS 支持的同步器属性。**

  确保两级复位同步触发器不会被优化、合并或跨级重定时，并尽量靠近放置。

- [ ] **步骤 4：添加窄范围约束。**

  约束对象必须精确匹配复位同步器的异步复位端，不能覆盖视频域普通数据路径、Pixel Clock 数据路径或 CFG 数据路径。

- [ ] **步骤 5：运行约束检查和完整 P&R。**

  确认 recovery 违例消失，同时正常数据路径仍然被时序分析；约束检查不能增加 error。

**验收：** `cfg_clk → video_pixel_clk` recovery WNS ≥ 0，且没有因全局 false path 导致有效路径数量异常减少。

---

### 任务 7：处理剩余 hold 和物理实现问题

**文件：**

- 工程：`boards/pgl50h/pds/pgl50h_rtl_synth`
- 重点报告：`place_route/*timing_summary*`、`report_timing/pgl50h_board_top.rtr`

- [ ] **步骤 1：在 setup 稳定后重新执行 PDS hold fix。**

- [ ] **步骤 2：定位最差 hold 路径的起点、终点和时钟偏斜。**

- [ ] **步骤 3：优先使用工具支持的 hold 修复和局部布局。**

- [ ] **步骤 4：只有工具无法修复时，才在对应短路径上增加功能等价的寄存器或受控延迟。**

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

- [ ] **步骤 8：生成下载文件并保存最终签核报告。**

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

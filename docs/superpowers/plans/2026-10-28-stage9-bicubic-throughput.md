# Stage 9 双三次吞吐优化实施计划

> 执行本计划时逐任务修改、验证和提交；基线提交为 `87b4709`（`new-algorithm`）。

**目标：**在保留 Catmull–Rom 双三次结果和 1280×720 视频链路的前提下，查明约 20–23 fps 的周期去向，逐步缩短单帧处理时间，并以同条件实板计数判断能否稳定达到 60 张新帧／秒。

**架构：**先给现有读取器增加每帧查询与缓存计数，不改像素数据通路。然后增加“整数源坐标窗口完全相同”时的零查询复用。若实测仍由查询次数限制，再在独立候选工程中把缓存从四个双端口 RAM bank 改为八个 bank，使新增的一列四个纵向像素可一次读取。

**工具：**SystemVerilog、Vivado Simulator 2020.2、PDS 2022.2-SP6.4、Fabric Debugger；DDR 处理时钟为 125 MHz。

## 已知证据与边界

- 2026-10-28 的 35 秒实板窗口：输入发布 2,110 帧，处理和显示各 801 帧，约 22.9 fps；最近帧约 5.49 M 周期，坐标阻塞约占 83.2%。用户另报告约 20 fps。先用同一位流、同一输入场景复测，不能把两种读数视为严格 A/B。
- 60 fps 的处理预算约 2,083,333 周期／帧，即 2.26 周期／像素。现有窗口复用命中时仍需两次 2×2 cache 查询，回退时需四次；cache 前端最多每周期接受一次查询。
- `pixel_tile_cache.sv` 的 bank 号为 `{local_y[0],local_x[0]}`。一列连续四行只落在两个 bank，每个 bank 需同周期读两次；因此上轮提出的“一次取新列”不能直接接在当前 RAM 上。
- `fill_state != FILL_IDLE` 或 S2 miss/retry 时，cache 令 `lookup_ready=0`；双像素上下文不能隐藏这段全局停顿。
- 基线 `.sbit/.fic` 已在提交 `87b4709` 中配对保存。后续候选必须生成同次构建的 `.sbit/.fic`；每次完整构建都检查 `All Constraints Met`，当前 setup WNS 仅 +0.049 ns。
- 保持 Brown 参数、单应矩阵、黑边规则、像素顺序、`frame_id`、`param_version` 和帧边界更新语义不变。不得只凭仿真周期宣称板上已达到 60 fps。

## 文件职责

| 文件 | 计划职责 |
|---|---|
| `fpga/project/stage9_bicubic_catmull_rom_multi_pixel_test/source/rtl/memory/cached_bicubic_neighbor_reader.sv` | 统计复用与 cache 查询；实现相同窗口零查询路径 |
| `.../source/rtl/correction/stage5_identity_pipeline.sv` | 将读取器诊断量传到帧引擎 |
| `.../source/rtl/memory/frame_identity_transform_engine.sv` | 在完整帧写排空时锁存诊断快照 |
| `.../source/rtl/fram_buf.v` | 导出带 `PAP_MARK_DEBUG` 的诊断信号 |
| `.../configure_angle_correction.py`、`.../Build-Stage9Bicubic.ps1`、`.../README_JTAG.md` | 定义、核对、解释 256 位 FIC 映射 |
| `.../sim/cached_bicubic_neighbor_reader_tb.sv`、`.../sim/stage9_bicubic_frame_tb.sv` | 保证输出顺序、数据、边界和反压不变 |

## Task 1：冻结并复核基线（已完成）

- [x] 把完整 PDS 工程定义、厂商 IP、RTL、仿真源和构建脚本提交到 `new-algorithm`。
- [x] 把当前匹配的 `.sbit/.fic` 强制纳入提交，分别核对 SHA-256 `63474F045EF12918E53173746D8C7B504647265EDB4740F44B6973371A88F74F` 和 `B4CB896ED443650531A9EDE33462928791122EEFCE895467FC7D420BA7AF13D5`。
- [x] README 更新到当前布局报告：setup WNS +0.049 ns，hold WHS +0.138 ns；提交 `87b4709` 已推送到 `origin/new-algorithm`。

## Task 2：测出查询与填充的真实比例

**修改文件：**上述读取器、流水顶层、帧引擎、`fram_buf.v`、FIC 配置脚本和 JTAG 说明。

**接口：**读取器新增两个 24 位每帧饱和计数输出 `reader_shift_reuse_count` 和 `reader_lookup_count`。在 `source_frame_start` 清零；分别在 `accept && can_reuse_window`、`lookup_fire` 时增加。经 `stage5_identity_pipeline` 传给帧引擎，帧引擎在 `WAIT_DRAIN` 成功发布帧时锁存为 `perf_reader_shift_reuse_count`、`perf_reader_lookup_count`。缓存现有的 `perf_cache_miss_count`、`perf_cache_fill_cycles` 继续使用。

- [ ] 在读取器的时序块加入带饱和保护的计数，不把 `s_valid` 未握手的周期算成像素，也不把 `cache_lookup_valid` 未握手的周期算成查询。核心条件如下：

  ```systemverilog
  if (source_frame_start) begin
      reader_shift_reuse_count <= 24'd0;
      reader_lookup_count <= 24'd0;
  end else begin
      if (accept && can_reuse_window && reader_shift_reuse_count != 24'hffffff)
          reader_shift_reuse_count <= reader_shift_reuse_count + 1'b1;
      if (lookup_fire && reader_lookup_count != 24'hffffff)
          reader_lookup_count <= reader_lookup_count + 1'b1;
  end
  ```

- [ ] 在读取器 testbench 中构造两个完整有效的连续窗口：第一个发四次查询，第二个向右移动一像素发两次；检查输出像素 ID 顺序、样本、`reuse_count=1` 和 `lookup_count=6`。另检查回退、黑边和输出反压不重复计数。
- [ ] FIC 保留原始 VSYNC、输入发布、处理完成、显示取新帧、READY 覆盖、错误、帧周期、坐标阻塞和状态等通道；把三项 32 位帧间等待字段共 96 位换成四项 24 位诊断字段：`perf_reader_shift_reuse_count`、`perf_reader_lookup_count`、`perf_cache_miss_count`、`perf_cache_fill_cycles`。同步更新构建脚本的通道检查和 `README_JTAG.md`。
- [ ] 运行 `sim/Run-Stage9BicubicReader.ps1`、`sim/Run-Stage9BicubicFrame.ps1 -FullHd`，再完整 PDS 构建。若出现负时序裕量，先对诊断布线做局部寄存／降扇出，不改变算法。
- [ ] 使用同次 `.sbit/.fic` 上板，在固定输入场景抓两次间隔约 60 秒的 Listing。帧计数取差；四项诊断和帧周期取最近完成帧快照。记录有效像素中的复用比例、平均查询数、miss 次数、fill 周期占帧周期比例。
- [ ] 提交诊断版及其 `.sbit/.fic`。所有被替换的 FIC 通道在 JTAG 说明中写清楚，避免用旧 FIC 解读新位流。

**决策：**若平均查询数接近 4／有效像素，优先 Task 3；若已接近 2 但 fill 周期仍占单帧的大块时间，优先 Task 5；若查询数约 2 且填充仅占小部分、仍远超 60 fps 预算，优先 Task 4。此处的比例由板上计数决定，不以猜测决定下一版架构。

## Task 3：相同整数窗口零查询复用

**修改文件：**`cached_bicubic_neighbor_reader.sv`、读取器 testbench、README。保持 cache 接口和插值器不变。

**接口：**将每个 context 的布尔 `ctx_reuse` 扩为二位 `ctx_window_mode`：`FULL=0`、`SHIFT_RIGHT=1`、`SAME=2`。`SAME` 需要前一已交付窗口，cache 查询数为零；每个像素仍使用自己的 `fx/fy`、元数据和像素 ID。

- [ ] 在 `can_reuse_window` 旁加入 `can_reuse_same`：要求前后整数 `x0/y0` 完全相同、当前 4×4 stencil 完整有效、源帧没有切换；只比较整数邻域，不比较 `fx/fy`。
- [ ] `input_query_total` 依次选择 `0`（SAME）、`2`（SHIFT_RIGHT）、`4`（FULL）。`SAME` 的 `m_samples` 使用 `last_output_window`；`SHIFT_RIGHT` 沿用现有三列移位和右侧一列的两个查询响应；两者都等待前一 context 的 `output_fire` 更新 `last_output_window_valid`。
- [ ] 读取器 testbench 检查 `FULL→SAME→SHIFT_RIGHT`、连续 SAME、不同 `fx/fy`、纵坐标变化回退、黑边、跨帧失效、反压。检查零查询像素的输出样本和 metadata，不允许将前一像素的 `fx/fy` 沿用。
- [ ] 运行读取器和 64×8、1280×720 双三次全帧仿真；按项目现有图像参考比较输出像素。完整 PDS 构建并确认时序；同场景上板比较 Task 2 的查询数、处理周期、处理／显示帧数。
- [ ] 只有当错误计数不增长且同条件周期明确降低时，提交该候选及其配套 `.sbit/.fic`。若收益很小，保留数据并转 Task 4 或 Task 5。

## Task 4：查询带宽不足时改为八 bank 单列读取

**前置条件：**Task 2/3 表明平均查询数导致单周期查询口接近饱和，而 fill 周期不足以解释主要停顿。此任务在独立的 Stage 9 候选工程中执行，保留 `87b4709` 的上板基线。

**修改文件：**候选工程中的 `pixel_tile_cache.sv`、`cached_bicubic_neighbor_reader.sv`、`tile_cache_bank_ram.sv` 的实例连接，以及对应 PDS、仿真和 JTAG 说明。

- [ ] 在 cache 请求加入 `lookup_shape`：`2X2` 保持现有四邻点顺序；`COL4` 返回同一 x、连续 y0..y3 的四个像素。两种请求均保留一进一出顺序和当前 4 像素响应接口。
- [ ] 把 bank 号从 `{local_y[0],local_x[0]}` 扩为 `{local_y[1:0],local_x[0]}`，实例化八个单读端口 bank。每个 bank 的 tile 深度从八个 128 位字减为四个，总像素存储量不变。填充一个 DDR 256 位 beat 时，偶数和奇数 x 的四个像素各写一个 bank；`bank_word_index` 对 32×4 tile 使用 `{set,way,local_x[4:3]}`。
- [ ] `2X2` 读取仍从四个不同 bank 取样；`COL4` 从同一 x 奇偶位对应的四个不同 y bank 取样。四个地址各自查 tag；跨 tile 边界时沿用 S2 单 miss、填充、重查机制，不允许漏填第二个缺失 tile。
- [ ] 读取器的 `SHIFT_RIGHT` 改为一次 `COL4` 查询，响应依序写入新窗口第 3 列的四行；`FULL` 仍发四次 `2X2`，`SAME` 仍发零次。响应 tag 中保留 context 和查询类型，保证两像素上下文与反压下仍按原顺序输出。
- [ ] 扩展 cache/reader testbench：覆盖全部四种 x/y 奇偶组合、x=31→32 和 y=3→4 跨 tile、两个缺失 tile 连续填充、查询与响应反压、同帧/跨帧 tag 失效。运行 1280×720 双三次全帧仿真，逐像素比较基线输出。
- [ ] 完整 PDS 构建，记录 LUT、DRM、setup/hold 裕量和最差路径；失败时先减少八 bank 读出多路选择与 tag 比较的组合深度。时序通过后才生成上板候选，并在同输入场景比较 Task 3 的周期和帧率。

**预期上限：**连续水平扫描的热路径查询数由 2 降到 1／像素；这仅解除查询端口的理论下限，DDR miss、帧写出和坐标链仍可能限制 60 fps。不得把 2 倍查询减少写成 2 倍实板帧率承诺。

## Task 5：若缓存填充占主导，先降低 miss

**前置条件：**Task 2 的 `perf_cache_fill_cycles` 与 `perf_cache_miss_count` 显示填充占主要帧时间。先做同容量候选，避免直接扩大为此前难以布线的 32×8 cache。

- [ ] 在 `host/` 新建一个离线 cache 地址轨迹分析脚本，输入当前标定参数包和测试单应矩阵，按现有 `tile_set_index()` 与 16×8 LRU 模拟每次 2×2 查询的 tile 命中／缺失；以现有 RTL 的小帧仿真 miss 顺序作一致性检查。
- [ ] 在模型中比较当前 `tile_x-tile_y+(tile_x>>2)` 哈希、`tile_x^tile_y` 和 `tile_x+3*tile_y`，只选择在目标角度轨迹上稳定降低 miss 且不增加容量的候选；边界、跨 tile 与多次重查按 RTL 语义计算。
- [ ] 仅对有明显模型收益的候选单独改 `tile_set_index()`，运行读者/全帧仿真、PDS 构建和同条件实板 A/B。记录 miss、fill 周期、总帧周期及最终时序；无收益则回退该候选。

## 验收和报告

- 每个候选记录 Git commit、`.sbit/.fic` SHA-256、PDS setup/hold 裕量、同一场景的原始输入／完整发布／处理完成／显示取新帧计数，以及最近完成帧周期和错误计数。
- 单帧目标为不高于约 2,083,333 个 125 MHz 周期；持续目标为处理和显示在约 60 秒窗口各增加约 3,600 张新帧，READY 覆盖不持续增长。单帧达标与持续吞吐须分别报告。
- 固定标定图和运动视频均检查 RGB、4×4 黑边、旋转裁切及错误灯。对 0° 和代表性的非零角度分别测量；角度变化会改变地址轨迹，不能只用单位矩阵的数字推断全部姿态。
- 若 Task 3 后仍有大幅缺口，按 Task 2 的读数在 Task 4 与 Task 5 中先选一个做；一次候选只改变一个主要结构，便于归因。

# Stage 3 双帧池原样复制记录

## 基线验收

- 日期：2026-10-20（据当前工作记录；用户未提供具体开始/结束时刻）
- 工程：`fpga/project/stage3_frame_pool_gate_fix`
- 板上结果：用户确认运动画面连续运行至少 30 分钟并通过。
- 输入运动图案、LED4–LED7 具体状态、硬件计数器数值：用户尚未提供；本记录不推定这些数值。
- 稳定修正版位流：`generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`
- 位流 SHA-256：`D52ADE23197CC6E318147A1C08F7AF91FD15B248FCECC39C757E28548B5B271B`
- 基线 PDS SHA-256：`2A3E9D920A1DA7E35E3244C89D756C5244C2BC0D4E01AE22EA4C00007AD9C8CF`
- 基线 `fram_buf.v` SHA-256：`558F7A80301AF51329C568ED5AB872C2300E9D652D62BBCE72371B0920B38DA5`
- 基线 `capture_pixel_gate.v` SHA-256：`7E74AB7CBC3695FC4F28940CEFC4D5BC795E39B0B6343CFFF5A22608497B8213`
- 基线 `wr_buf.v` SHA-256：`8B38525BDF31E754BA7A6ACA6B0653F43FC819D42CD10074D100F0EA7C768F34`
- 基线 `rd_buf.v` SHA-256：`5600C0898E2199B09D943606D2B78C28C2A0F1D117A3A24C7A61E86E53EC64FC`
- DDR3 IP wrapper `ddr3_test.v` SHA-256：`3C5441B4BFF33DFF73811C3A025EDE3B6348CB5779E21778653659B6CBFB84E0`

## 独立副本基线构建

- 生成器：`fpga/project/New-Stage3DualPoolCopyProject.ps1`
- 副本：`fpga/project/stage3_dual_pool_copy`
- 来源：`fpga/project/stage3_frame_pool_gate_fix`
- 已复制 239 个工程输入文件；生成目录和本地构建日志未从源工程复制。
- PDS：2022.2-SP6.4，器件 PG2L200H-6FBB676。
- Compile：2026-10-20 16:08，rtl-analyze/compile 完成。
- Synthesize：2026-10-20 16:11，日志报告 `Design 'HDMI_IN_DDR3_HDMI_OUT_top' has been successfully synthesized` 和 `Process "Synthesize" done.`；输出网表 `synthesize/HDMI_IN_DDR3_HDMI_OUT_top_syn.vm`，约 7.77 MB。
- 网表检查：保留 `capture_pool` 与 `pixel_gate`；这仍是门控修正版的单池采集到显示路径。
- 构建提示：日志包含 SDPRAM IP 器件信息为 PG2L100H、与顶层 PG2L200H 不一致的警告；另有视频 RGB、LED 和 VS 输入未约束提示。这些提示与基线工程一同复制，尚未作为本阶段修改内容处理。
- PDS 控制台完整日志：`fpga/project/stage3_dual_pool_copy/baseline-synthesize.log`（由 `.gitignore` 排除）。

## 当前状态

独立工程副本可重新生成。双帧池、原样复制器、显示读适配器及四客户端 DDR 读写仲裁已经接入，候选位流已生成。定向仿真、四客户端合成 DDR 模型集成仿真和 PDS 全流程通过；实板画面、实际帧率及 30 分钟稳定性尚待验收。

## 事务语义审计与写排空修正

- 依据 Pango《Chapter 2 IP User Guide》（UG022003 V1.6）2.5.2.1：AW/AR 握手是 `VALID && READY`，LEN 字段表示 `LEN + 1` 拍，地址与 ID 等信息要保持稳定到握手；Pango 简化 DDR 接口没有写响应通道，读返回以 `RVALID` 和 `RLAST` 标记有效与末拍，接口没有 `RREADY`。
- 同指南写数据通道说明：`axi_wready` 为数据传输有效指示，`axi_wusero_last` 标记末拍，`axi_wusero_id` 与数据拍同步。因此排空完成事件改为 `axi_wready && axi_wusero_last`，并按同步的 ID 0/1 分别计数。
- 原 `ddr_write_drain_tracker` 只对 `wusero_last` 上升沿计数，可能在 `axi_wready=0` 时错误地把帧报告为空闲。新增回归场景先在 `axi_wready=0` 时拉高末拍标志；修正前 Vivado Simulator 报告该断言失败，修正后通过。
- 修正文件：`fpga/rtl/memory/ddr_write_drain_tracker.v`；调用接线更新到 `fpga/sim/frame_pipeline_smoke_top.v`、新双池工程 `fram_buf.v`/综合 smoke top 和工程生成器。已验收的 `stage3_frame_pool_gate_fix` 不作改动。
- Vivado Simulator 2020.2：`Run-DdrWriteDrainTracker.ps1` 通过；失败扫描同步修正为识别 `FAIL at`，避免测试脚本把 `$fatal` 输出误判为通过。
- Vivado Simulator 2020.2：`Run-FramePoolAddress.ps1` 通过，六槽映射和帧字地址边界检查通过。
- 更新后的 `stage3_dual_pool_copy` 在 PDS 2022.2-SP6.4 完成 Compile 与 Synthesize；合成日志含 `Process "Synthesize" done.`，成功综合网表已生成。
- `fram_buf.v` 已用 `frame_pipeline_ownership` 取代单一采集/显示共享池：采集准入驱动输入池 producer，输出 VS 边界请求只向输出池取帧，写地址仍取输入槽号。复制控制在此阶段保持关闭，避免把未写入的数据发布到输出池。
- PDS 2022.2-SP6.4 Compile/Synthesize 通过；综合网表中保留 `frame_pipeline_ownership ownership`、`frame_pool_manager capture_pool` 和经工具唯一化命名的 `output_pool` 实例。最初的网表检查脚本只匹配未唯一化模块名，后经直接检查确认两个池均存在。
- Vivado Simulator 2020.2：`Run-CaptureFrameControl.ps1` 与 `Run-FramePipelineOwnership.ps1` 均通过，分别覆盖整帧准入/门控和双池槽位交接、复制失败与最新帧保留。
- 在此中间阶段，输出池在复制器接通前保持空池，HDMI 输出为黑场；随后已接通复制器并生成候选位流。已验收门控修正版保持可回退。
- 工程生成器已同步扩展为生成双池所有权顶层，并同步公共 `ddr_write_drain_tracker.v` 和 smoke top；脚本通过 PowerShell 语法解析检查。
- Pango 官方接口说明：[Chapter 2 IP User Guide（PDF）](https://www.pangomicro.com/en/uploads/59186237_1711509831.pdf)。接口仿真和文档确认尚未替代实板 DDR 写后读回验证。

## 显示读适配（任务 4 的中间构建记录）

- 新增 `display_read_adapter.v`：将整行请求拆为最多 16 拍的 DDR 突发；每次 AR 握手前根据 512×256 位行缓冲的写入拍数、像素侧 Gray 码消费拍数和已预留的返回拍数计算空间。突发返回完整后再提交下一突发；一整行全部返回时才发 `line_done`。
- 新工程 `rd_buf.v` 导出单调递增的 10 位 Gray 码消费计数；每消费 8 个 32 位像素计一拍。显示有效信号在像素域同步后才允许 RAM 读指针前进。每次 VS 重置物理 RAM 指针，适配器在没有在途读时将逻辑写计数对齐到已同步的消费计数；跨 VS 尚有在途读时锁住新帧请求并报错。
- 修正公共 `ddr_read_burst_arbiter.v`：当 `ARVALID=1` 且 `ARREADY=0` 时锁住已选客户端、地址和长度。新增回归先复现竞争客户端加入后地址/长度变化，修正后通过。
- Vivado Simulator 2020.2：`Run-DisplayReadAdapter.ps1` 通过，覆盖 512 拍占满后停止、释放 16 拍再发、逐拍数据次序和下一帧重新计数；`Run-DdrReadBurstArbiter.ps1` 通过。
- 在当时的中间构建中，新工程 `fram_buf.v` 已将显示端连接到适配器和读仲裁器，AR 地址使用输出池物理槽 3–5。PDS Compile 和 Synthesize 通过。复制器那时尚未接通，输出池恒空，综合网表会把显示读逻辑优化掉；因此该次综合只证明当时 RTL 可编译。后续四客户端构建已保留显示读实例，见下节。
- 新工程 `rd_buf.v` 将行请求保持到适配器接受，并在上一行完成脉冲期间禁止下一行握手，防止旧行地址被重复请求。`Run-DisplayLineRequest.ps1` 双时钟定向仿真通过，覆盖请求等待、输出槽地址、行完成后地址前进和帧完成。修改后的 PDS Compile 再次通过。
- 工程生成器已同步读路径改动；用临时 `stage3_dual_pool_copy_regen_check` 副本重生 239 个基线输入文件，再补齐模块及接线，PDS Compile 通过。临时目录的递归清理被自动审批策略以 `blocked by policy` 拒绝，目录保留并已在 `.gitignore` 排除；这不影响正式工程。
- 此中间阶段待完成的读 `RID` 检查、复制读客户端和异常帧屏蔽已在后续集成中接入；实板上的像素域消费与 DDR 返回并行行为仍待验证。

## 四客户端集成与候选位流

- 写仲裁器 `ddr_write_burst_arbiter.v` 将采集写作为 ID 0、复制写作为 ID 1；AW 等待期间保持地址、长度及 ID，W 数据所有者锁定到合格末拍。`Run-DdrWriteBurstArbiter.ps1` 覆盖交替所有者和错误末拍 ID，通过。
- `frame_copy_engine.v` 每帧复制 7200 个 16 拍突发，从输入槽 0–2 原样写到输出槽 3–5，只有最后一拍写排空后才报告完成。`Run-FrameCopyEngine.ps1 -FullFrame` 比较了 115200 个 256 位拍内的全部 921600 个不同的 32 位字及源/目标地址，通过；短读故障用例确认不发布部分帧。
- `Run-FourClientDdrIntegration.ps1` 以合成 DDR 模型同时驱动显示/复制读及采集/复制写，验证读返回归属、写数据所有者、ID 1 排空和输出池 READY/显示交接，通过。该模型不等同于 Pango DDR IP 或实板带宽测试。
- `Run-DisplayReadAdapter.ps1`、`Run-DisplayLineRequest.ps1`、`Run-DdrReadBurstArbiter.ps1`、`Run-DdrWriteDrainTracker.ps1`、`Run-FramePoolAddress.ps1`、`Run-CaptureFrameControl.ps1`、`Run-FramePipelineOwnership.ps1` 均通过。显示适配器为 512×256 位缓冲预留返回空间，异常时屏蔽显示；读仲裁检查 RID，并在 ARREADY 拉低时保持 AR 稳定。
- 后续复核发现：原适配器只在拟发下一笔 AR 时检查缓冲越界，像素侧在最后一笔 DDR 读后越过已写数据可能漏报。新定向用例先复现 `protocol_error_count=0`、`frame_blocked=0` 的失败，再改为持续检查已写与已消费的模距离；欠读时锁存错误、停止接收并阻止后续行。修正后 `Run-DisplayReadAdapter.ps1`、`Run-FourClientDdrIntegration.ps1` 和 `Run-DisplayLineRequest.ps1` 通过；正式工程已用相同公共 RTL 重建。
- PDS 2022.2-SP6.4 的 Compile、Synthesize、Device Map、Place & Route、Report Timing、Generate Bitstream 全部完成。综合网表保留复制器、显示适配器、双池管理器及读写仲裁器，合成报告为 0 latch。
- `report_timing/HDMI_IN_DDR3_HDMI_OUT_top.rtr` 报告受约束路径 `All Constraints Met`。慢角建立余量：DDR 125 MHz 域 +1.087 ns、输入像素 74.25 MHz 域 +8.343 ns、输出 PLL 74.25 MHz 域 +7.751 ns。沿用基线约束，HDMI RGB/同步外部端口仍有未约束路径，因此不据此宣称全部板级接口时序已证明。
- 候选位流：`fpga/project/stage3_dual_pool_copy/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`，9,188,552 字节，SHA-256 `34A3553698AEEFA91A9B4F61311767BEEA7210F825E76FBA2C002DF06B414CB8`。构建日志：`fpga/project/stage3_dual_pool_copy/candidate-bitstream-build.log`（本地保留、由 `.gitignore` 排除）。
- `fram_buf.v` 中的复制完成/错误、采集丢弃、读写协议错误、输出帧序号和写在途计数等信号带 `PAP_MARK_DEBUG`，网表中可核查。尚未建立并验证 PDS 实板读取这些计数器的流程。LED4/5/6/7 分别锁存“原始 DE 到达 / 通过门控的像素到达 / 输入完整帧发布 / 输出池帧已供显示”；灯亮是曾发生的里程碑，不表示持续无错。
- 板级待验：上板画面和 RGB 顺序、逐帧编号运动画面的不同帧吞吐、重复显示与丢弃原因、行缓冲欠读、协议错误、LED 状态、闪屏/错行/撕裂、持续至少 30 分钟。新候选位流未标记为已验收，回退位流保持上文哈希。

### 实板记录顺序

1. 下载上述候选位流，记录上电后 LED4–LED7 是否依次达到里程碑，并确认 HDMI 输出分辨率/刷新率。若输出异常，记录出现时间及灯态，以已验收门控修正版位流回退。
2. 依次输入纯色/交替色、静态棋盘格、带独立逐帧编号的运动画面，观察 RGB 顺序、首末行、错行、撕裂、闪屏及黑场；记录各图案的开始/结束时间和画面证据。
3. 使用运动画面连续运行至少 30 分钟，记录 LED 变化和异常发生次数。若能通过 PDS 调试读取内部信号，再记录 `copied_count`、`copy_error_count`、`capture_dropped_count`、`output_dropped_count`、`display_read_error_count`、`read_arbiter_error_count`、`write_arbiter_error_count`、`write_protocol_error_count` 和 `displayed_sequence` 的起止值；先确认读出方法，不能把未读取数值记为 0。
4. 对独立逐帧编号源，按实际输出的不同帧编号或 `copied_count` 增量估算处理帧率；HDMI 维持 60 Hz 只能证明输出时序，不能代替复制帧吞吐测量。

首次实板出现持续黑屏的观察、故障边界分析和独立 LED 诊断位流见 `docs/results/stage3-dual-pool-black-screen.md`。

# 阶段 2：720p60 DDR3 视频缓存基线

## 工程配置

- 板卡：PG2L200H/FBB676/-6，源自厂商 `4_10_timing/4_10_HDMI_IN_DDR3_HDMI_OUT`。
- 视频输入：MS7200 EDID 仅声明 1280×720@60 Hz；像素时钟约束 13.468 ns。
- 视频输出：PLL 27 MHz → 74.25 MHz，1280×720 有效区，1650×750 总时序。
- DDR3：沿用厂商控制器和 RGB565 双帧缓存。行写入 640 个 32 位字，每帧 460,800 个字；`fram_buf` 将 `LINE_ADDR_WIDTH` 覆盖为 22，帧槽起点相差 2²² 个字。
- 本地 PDS 工程：`fpga/project/stage2_ddr3_720p60/HDMI_IN_DDR3_HDMI_OUT.pds`。

## 构建与上板记录

| 项目 | 结果 |
| --- | --- |
| PDS bitstream 构建 | 2026-10-19 用 PDS 2022.2-SP6.4 构建成功；`generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit` |
| DDR3 初始化指示 | 待上板确认 |
| HDMI 输入活动信号 | 待上板确认 |
| HDMI 输出活动信号 | 待上板确认 |
| 静态纯色/棋盘格显示 | 用户反馈显示大体正常；测试图种类待记录 |
| 运动画面撕裂/错行 | 用户反馈约每 5–6 秒出现一次短暂错位闪动 |
| 连续运行时间 | 待上板确认 |
| FPGA 内部时序 | 报告显示 `All Constraints Met`；输出像素时钟 74.2501 MHz，最差建立余量 7.478 ns；DDR 控制域 2.317 ns |

本阶段位流仍是 RGB565 链路。RGBX8888、完整帧槽握手、丢帧/欠读计数和畸变矫正尚未接入。厂商 `wr_fram_buf.idf`、`rd_fram_buf.idf` 的器件元数据写的是 PG2L100H/FBG484；PDS 会发出与当前项目不一致的警告，应在正式版检查或重新生成相应 IP。

时序报告中 HDMI RGB/同步输入和输出端口缺少片外输入、输出延迟；`All Constraints Met` 只说明已约束的路径通过，不代表板级接口余量已经确认。DDR3 初始化与画面稳定性仍需下载位流后在板上记录。

## 闪动问题定位

2026-10-19 用户反馈：LED0 闪烁，LED1–3 稳定，画面约 5–6 秒短暂错位一次。`heart_beat_led` 接 LED0，其 RTL 规定 DDR3 初始化完成后周期翻转，因此 LED0 闪烁是正常心跳。LED1=`ddr_init_done`，LED2=`init_over_rx`，LED3=`hdmi_int_led`。

使用 `fpga/project/Add-Stage2Diagnostics.ps1` 可在本地 PDS 工程中加入 LED4–7 锁存诊断，重新构建位流。诊断标志按高电平输出；观察重点是复位后某灯是否在闪动时改变状态，四灯均可通过板卡复位键清零。LED4/5 在 DDR 初始化约 2 秒后开始监测，跳过启动阶段。

诊断位流已于 2026-10-19 构建成功，路径为 `fpga/project/stage2_ddr3_720p60/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top_diagnostic.sbit`；已约束内部路径仍显示 `All Constraints Met`。LED4–7 管脚来自同板卡厂商 LED 例程：A17、A18、C17、B17。

| 灯 | 置位条件 | 可疑环节 |
| --- | --- | --- |
| LED4 | 新的写行请求到达时，上一写命令仍未就绪 | 采集写入/DDR 调度 |
| LED5 | 新的读行请求到达时，上一读命令仍未就绪 | 显示读取/DDR 调度 |
| LED6 | DDR 初始化曾成功，之后短暂掉线 | DDR 控制器、时钟或复位 |
| LED7 | 输入帧有效像素数不等于 1280×720 | HDMI 输入时序/DE |

这些标志帮助定位原因，但即使全部不亮，也不能排除独立输入/输出时钟的帧槽追帧。厂商双帧缓冲独立按两侧 VS 翻转帧槽，没有完整帧所有权握手，这是后续必须修正的结构风险。

### 诊断位流回退

用户上板诊断位流后反馈：画面出现持续的大块重复、错位；LED0 闪烁，LED1–3 亮且稳定，LED4–7 全暗。诊断位流相对先前 RGB565 基线造成明显回退，应停止使用；LED4–7 未观察到置位，不足以说明帧缓存没有问题。已从厂商源文件重新生成无诊断逻辑的 720p60 基线工程 `stage2_ddr3_720p60_baseline_restore/`，并保留诊断工程供差异分析。

恢复位流路径：`fpga/project/stage2_ddr3_720p60_baseline_restore/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`。2026-10-19 PDS 构建成功，内部时序报告为 `All Constraints Met`；用户上板确认画面恢复为大部分稳定、偶尔错位闪屏，LED1–3 稳定。

### 共享像素时钟对照实验

2026-10-19 继续排查：基线写端在输入 VS 时翻转 DDR 帧槽，读端在输出 VS 时独立翻转；`wr_buf.frame_wcnt` 未接到读端，`rd_buf.init_done` 虽接入但未被使用。两端没有完整帧所有权握手。输出时钟由 27 MHz 晶振经 PLL 得到 74.25 MHz，输入时钟来自 HDMI 接收芯片；若两者实际频率略有差异，帧相位会缓慢漂移。源码结构支持这个假设，但尚未得到上板证实。

为单独检验时钟漂移，运行 `fpga/project/New-Stage2SharedClockProject.ps1` 可生成 `stage2_ddr3_720p60_shared_clock/`：仅将输出 `pix_clk` 改接 `pixclk_in`，PLL 仍保留给原有 `locked` 初始化逻辑。FDC 同步移除已不存在的独立 `pix_clk` 时钟组。未改 DDR 帧槽、命令或视频数据逻辑。

独立位流：`fpga/project/stage2_ddr3_720p60_shared_clock/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`。PDS 2022.2-SP6.4 构建成功，内部报告为 `All Constraints Met`，`pixclk_in` 约束 13.468 ns、建立余量 7.924 ns；HDMI RGB/同步片外延迟仍未约束。此位流是 A/B 定位用版本，等待用户上板观察；已确认可显示的恢复版位流保留原路径。

上板时保持电脑输入为活动信号 1280×720@60 Hz，先确认画面完整，再连续观察至少 1–2 分钟并记录是否仍出现约每 5–6 秒错位闪屏。若不再闪，优先处理独立时钟与帧槽所有权；若仍闪，转查 DDR 行请求丢失、环形行缓存和板级 I/O 时序。LED0 是心跳，不能当作故障指示。

用户随后反馈共享像素时钟对照版闪屏更快。故单纯输入/输出频率差不是充分解释；不要继续把该位流作为稳定版本使用。后续分析以恢复版为基准，重点检查帧槽所有权与行请求丢失。对照版更快可能与帧相位固定后的读写碰撞有关，也可能与布局、I/O 时序有关，尚无上板证据可区分。

### 底部黑色缺口与末行预取

用户提供恢复版画面照片：白色任务栏底边出现输入电脑画面没有的数段黑色缺口。再次检查 `rd_buf.v` 的输出行预取计数：输出 VS 到来时 `wr_line` 置 1 并预取第 1 行，随即加到 2；有效区第 1～719 行开始时应预取第 2～720 行。厂商条件 `wr_line != V_NUM` 在 `wr_line == 720` 时停止，因此只发出 719 次读行请求，第 720 行显示时仍会继续从环形行缓存取数据。这个确定的计数错误可解释底部旧像素/黑色缺口，但不能单独解释每隔数秒的整屏错位。

新增 `fpga/project/New-Stage2LastLineProject.ps1`，从同一厂商基线重新生成独立工程 `stage2_ddr3_720p60_last_line/`，仅将读行条件改为 `wr_line <= V_NUM`。VS 预取第 1 行，有效区第 1～719 行各预取下一行，有效区第 720 行停止，合计 720 行。原输出 PLL、输入像素时钟、DDR 控制和顶层连接均与恢复版一致。

位流：`fpga/project/stage2_ddr3_720p60_last_line/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`。2026-10-19 PDS 2022.2-SP6.4 构建成功，已约束路径报告 `All Constraints Met`。用户上板反馈“完美解决”，并连续运行至少 30 分钟，未复现底部黑边、错位或闪屏。原恢复版位流仍保留。

RGB565 画面稳定性验收已通过。后续补丢帧和欠读计数，再推进完整帧槽交接与 RGBX8888 升级。压缩记录见 `docs/chat/2026-10-19-720p60-ddr3-debug-summary.md`。

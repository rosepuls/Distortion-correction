# Stage 12 吞吐诊断 FIC

本 FIC 将 256 个触发通道用于同时观察帧率和处理等待。修改 `debug_core.fic` 后，需重新运行本工程 PDS 构建。烧录时必须使用 `generate_bitstream/` 内同一构建生成的 `.sbit/.fic` 配对文件。

## 通道表

| 通道 | 信号 | 用途 |
|---|---|---|
| 0–15 | `fram_buf/raw_input_vsync_count[15:0]` | 原始输入 VSYNC 帧数，16 位回绕 |
| 16–31 | `fram_buf/input_published_count[15:0]` | 输入帧池已发布帧数低 16 位 |
| 32–47 | `fram_buf/copied_count[15:0]` | 成功处理完成帧数低 16 位 |
| 48–63 | `fram_buf/display_take_count[15:0]` | 显示侧取用输出帧数低 16 位 |
| 64–79 | `fram_buf/capture_dropped_count[15:0]` | 输入帧池 ready 队列溢出/丢弃计数 |
| 80–95 | `fram_buf/output_dropped_count[15:0]` | 输出帧池 ready 队列溢出/丢弃计数 |
| 96–119 | `fram_buf/perf_frame_cycles[23:0]` | 最近完成帧的处理周期数，饱和计数 |
| 120–143 | `fram_buf/perf_coord_stall_cycles[23:0]` | 最近完成帧的坐标提交等待周期 |
| 144–167 | `fram_buf/perf_cache_fill_cycles[23:0]` | 最近完成帧的 Cache 行回填等待周期 |
| 168–191 | `fram_buf/perf_read_first_beat_wait_cycles[23:0]` | 最近完成帧的 DDR 读请求到首拍等待周期 |
| 192–207 | `fram_buf/perf_cache_miss_count[15:0]` | 最近完成帧 Cache miss 次数低 16 位 |
| 208–231 | `fram_buf/perf_output_backpressure_cycles[23:0]` | 最近完成帧结果端被输出双缓冲反压的周期 |
| 232–255 | `fram_buf/perf_read_arbiter_wait_cycles[23:0]` | 最近完成帧等待 DDR 读仲裁的周期 |

## 测量帧率

在 Fabric Debugger 中记录一次计数快照，等待已知时长后再次运行并记录。平均帧率按 `Δ帧数 / Δ秒` 计算：

- 输入到达速率：`raw_input_vsync_count` 或 `input_published_count`
- 图像处理完成速率：`copied_count`
- 显示取帧速率：`display_take_count`

`raw_input_vsync_count` 与三项帧计数均按 16 位差值取模；READY 丢弃计数在 `0xFFFF` 饱和。建议固定输入画面与参数，用 30–60 秒窗口采两次快照并记录时间；帧率按计数差除以秒数计算。最近完成帧的性能计数是单帧快照，直接读取终点值，不对两次快照相减。Cache miss 仅映射低 16 位，当前帧 miss 低于 65536 时可直接读取。

比较输入发布、处理完成和显示取帧的窗口增量，先确定帧率在哪一级下降。`perf_coord_stall_cycles` 高表示坐标请求被下游反压；用 `perf_output_backpressure_cycles` 判断结果端是否被输出缓冲阻塞，再结合 Cache 回填、DDR 首拍和读仲裁等待定位来源。这些周期可能重叠，不能相加。

## 构建与采集

1. 在本工程运行 `Build-Stage12SuperResolution.ps1` 完成完整 PDS 构建。确认 PDS 成功生成位流，并检查报告中的时序状态；脚本会明确警告时序未闭合的构建，同时输出配套 `.sbit/.fic` 哈希。
2. 烧录配套文件，固定输入源、UART 姿态矩阵和灯光 profile。两次 Debugger 快照间隔 30–60 秒。
3. 新列名应在 `output_dropped_count` 后显示帧周期、坐标停顿、Cache 回填、DDR 首拍、Cache miss、输出反压和 DDR 读仲裁计数。若仍显示旧错误计数列，说明当前导入的 FIC 不是本次构建配套文件。
4. 记录所有计数及时间戳，更新到 `docs/chat/super-resolution.md`，再决定 RTL 优化假设。

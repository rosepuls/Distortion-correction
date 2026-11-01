# Stage 8 帧率与掉帧计数探针

本 FIC 将 256 个触发通道用于帧计数和处理负载诊断。需要重新运行 PDS 并生成新 `.sbit` 后，使用 `generate_bitstream/` 内同一构建生成的 `.fic`；旧 sbit 与此版 FIC 不匹配。

## 通道表

| 通道 | 信号 | 用途 |
|---|---|---|
| 0–15 | `fram_buf/raw_input_vsync_count[15:0]` | 原始输入 VSYNC 帧数，16 位回绕 |
| 16–47 | `fram_buf/input_published_count[31:0]` | 成功发布到输入帧池的帧数，饱和计数 |
| 48–79 | `fram_buf/copied_count[31:0]` | 成功处理完成的帧数，饱和计数 |
| 80–111 | `fram_buf/display_take_count[31:0]` | 显示侧取用输出帧数，饱和计数 |
| 112–127 | `fram_buf/capture_dropped_count[15:0]` | 输入帧池 ready 队列溢出/丢弃计数 |
| 128–143 | `fram_buf/output_dropped_count[15:0]` | 输出帧池 ready 队列溢出/丢弃计数 |
| 144–159 | `fram_buf/capture_rejected_count[15:0]` | 输入帧因无法接纳而拒绝的计数 |
| 160–175 | `fram_buf/capture_abort_count[15:0]` | 输入采集被中止的计数 |
| 176–191 | `fram_buf/incomplete_output_count[15:0]` | 输出 VSYNC 到来时前一帧仍不完整的次数 |
| 192–207 | `fram_buf/copy_error_count[15:0]` | 处理错误计数低 16 位 |
| 208–231 | `fram_buf/perf_frame_cycles[23:0]` | 最近完成帧的处理周期数；超过 24 位范围会饱和 |
| 232–255 | `fram_buf/perf_coord_stall_cycles[23:0]` | 最近完成帧的坐标等待周期数；超过范围会饱和 |

## 测量帧率

在 Fabric Debugger 中记录一次计数快照，等待已知时长后再次运行并记录。平均帧率按 `Δ帧数 / Δ秒` 计算：

- 输入到达速率：`raw_input_vsync_count` 或 `input_published_count`
- 图像处理完成速率：`copied_count`
- 显示取帧速率：`display_take_count`

`raw_input_vsync_count`、`capture_rejected_count` 和 `capture_abort_count` 是 16 位回绕计数，差值按 65536 取模。ready 丢弃计数和 `incomplete_output_count` 在 `0xFFFF` 饱和；饱和前比较增量，饱和后只能判断曾发生很多次，不能继续统计增量。32 位帧计数在 `0xFFFFFFFF` 饱和。建议用 30–60 秒窗口，并确保用于帧率的计数没有达到饱和值。Fabric Debugger 单次 512 深度采样本身覆盖时间很短，帧率应通过两个有时间标记的快照求平均，不能直接把单次 Listing 行频率当作 FPS。

比较 `input_published_count`、`copied_count`、`display_take_count` 的窗口增量可区分输入接纳、处理完成和显示取用哪一段开始落后。再看 drop/reject/abort/incomplete 计数是否增长；`perf_frame_cycles` 与 `perf_coord_stall_cycles` 可判断最近完成帧的耗时及坐标等待占比。若这几项错误计数均不增长但处理帧率仍下降，下一步需增加更细的 DDR/cache 分阶段周期探针。

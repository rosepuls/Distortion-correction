# Stage 9 帧处理与帧间等待诊断通道

必须将本诊断工程生成的 `.fic` 与同次 `.sbit` 配对使用。抓取两次 Listing，记录 Fabric Debugger Console 的时间，间隔建议 15–60 秒。

| 通道 | 信号 | 含义 |
|---|---|---|
| 0–15 | `raw_input_vsync_count` | 输入 VSYNC 次数 |
| 16–31 | `input_published_count[15:0]` | 已写入 DDR 并发布的完整输入帧 |
| 32–47 | `copied_count[15:0]` | 已完成校正、写回并发布的输出帧 |
| 48–63 | `display_take_count[15:0]` | 显示端取得新处理帧的次数 |
| 64–79 | `capture_dropped_count` | 发布新帧时覆盖 READY 输入帧的累计数 |
| 80–87 | `perf_error_flags[7:0]` | 当前工程映射的错误标志 |
| 88–119 | `perf_frame_cycles` | 最近完成帧从 copy start 到 DDR 写排空的周期数 |
| 120–151 | `perf_coord_stall_cycles` | 最近帧中坐标请求被阻塞的周期数 |
| 152–183 | `copy_gap_max_cycles` | 最近记录到的最大帧间 copy 等待周期数 |
| 184–215 | `gap_input_at_max` | 最大帧间等待中缺少可处理输入帧的周期数 |
| 216–247 | `gap_output_at_max` | 最大帧间等待中没有可用输出槽位的周期数 |
| 248–255 | `perf_diag_state` | 当前帧池、copy 活动状态 |

`perf_diag_state` 位定义为 `{copy_physical_drained, copy_start_ready, display_valid, allow_capture, capture_begin_ready, copy_wait_output, copy_wait_input, copy_active}`。

所有周期计数为 32 位饱和计数；在 125 MHz 下上限约 34.36 秒。根据计数增量计算输入发布、算法完成和显示取新帧速率：`Δcount / Δseconds`。`perf_frame_cycles` 反映单帧活跃时间，`copy_gap_max_cycles` 反映帧间空档；二者可区分计算慢与调度等待。`gap_input_at_max` 与 `gap_output_at_max` 仅对应记录到的最大空档。

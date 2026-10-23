# Stage 5 算法帧率实测

_2026-10-22 实板运动画面测量。_

## 诊断位流

独立工程 [`stage5_identity_fps_debug`](../../fpga/project/stage5_identity_fps_debug/README.md)保留了 DDR Tile Cache 单位映射处理器，同时增加输入帧发布和显示取帧计数，并插入 256 通道 Fabric DebugCore。PDS 2022.2-SP6.4 全流程通过，DDR 125 MHz 建立时间裕量 +0.622 ns，所有约束满足。

配套文件必须来自同一次构建：

- [位流 `.sbit`](../../fpga/project/stage5_identity_fps_debug/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit)，SHA-256 `65E369284448C066BF31C1D7003FD3CEE41E066B9F570286E7C056C94FCD2CF6`。
- [调试配置 `.fic`](../../fpga/project/stage5_identity_fps_debug/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic)，SHA-256 `75238CA445B2684E35A16E4364A69EB8E04D31BDA685E78D9481FAC6DD5DCB97`。

Stage 3 的诊断位流和 `.fic` 测的是旧帧复制路径，不能用于本次 Stage 5 算法帧率结论。普通 Stage 5 位流的 LED4/5 常暗、静态图完整已另行记录在[Stage 5 结果](stage5-identity-ddr.md)。

## 测量步骤

1. 源电脑选 1280×720、60 Hz HDMI 模式，打开 [`rgbx8888_link_test.html`](../../host/test_patterns/rgbx8888_link_test.html) 的运动帧号图案，记录网页自身显示的浏览器 FPS。它是源端数据，不当作 FPGA 输出帧率。
2. 在 Pango Fabric Debugger 烧录上述诊断 `.sbit`，导入配套 `.fic`，连接 `CORE:0 MyFLA0`。选择 **Trigger Immediate**，在 Listing 中取最后一行，保存 Console 时间及下表计数。
3. 约 60 秒后重复捕获。按实际时间差计算 `输入发布 fps = Δinput_published_count / Δt`、`算法完成 fps = Δcopied_count / Δt`、`显示新帧 fps = Δdisplay_take_count / Δt`。例如 60.0 秒内完成 3600 帧即 60.0 fps。
4. 比较 `capture_dropped_count`、`output_dropped_count`、`copy_error_count`、`incomplete_output_count` 和读写错误计数的增量，再运行运动画面 30 分钟做起止比较。错误计数未读到的字段记为“未观测”，不记为零。

| Listing 通道 | 信号 | 作用 |
| --- | --- | --- |
| 0–23 | `input_published_count[23:0]` | 完整输入帧已写入并发布 |
| 24–47 | `display_take_count[23:0]` | 显示在帧边界取得新的完整输出帧 |
| 48–79 | `copied_count[31:0]` | 算法完成并发布输出帧 |
| 80–111 | `copy_error_count[31:0]` | 处理所有权错误 |
| 112–143 | `displayed_sequence[31:0]` | 当前显示输出帧序号 |
| 144–255 | 其余丢帧和协议错误计数 | 详见[完整通道表](../../fpga/project/stage5_identity_fps_debug/README_JTAG.md) |

显示器报告 60 Hz 只说明 HDMI 刷新时序；显示取帧计数可能低于 60 fps 而屏幕仍保持 60 Hz。即使三个硬件计数都接近 60 fps，仍需观察运动帧号，排除源电脑输出重复画面。

## 实板读数（运动画面）

两次 Debugger Listing 的最新触发时间分别为 12:22:11 和 12:23:12，间隔 **61 秒**。两张截图： [12:22:11](stage5-fps-listing-12-22-11.png)、[12:23:12](stage5-fps-listing-12-23-12.png)。计数为十六进制，按无回绕的本次增量换算：

| 项目 | 第一次 | 第二次 | 增量 | 速率/结论 |
| --- | ---: | ---: | ---: | ---: |
| Console 最新触发时间 | 12:22:11 | 12:23:12 | 61 s | — |
| `input_published_count` | 0x005A9C (23,196) | 0x0068DC (26,844) | 3,648 | **59.80 fps** |
| `copied_count` | 0x00002C1A (11,290) | 0x0000330A (13,066) | 1,776 | **29.11 fps** |
| `display_take_count` | 0x00002C1A (11,290) | 0x0000330A (13,066) | 1,776 | **29.11 新帧/s** |
| `capture_dropped_count` | 0x2E80 (11,904) | 0x35D0 (13,776) | 1,872 | **30.69 帧/s 丢弃** |
| `output_dropped_count` | 两次均显示 0 | 两次均显示 0 | 0 | 截图可见字段未增加 |
| `copy_error_count` | 两次均显示 0 | 两次均显示 0 | 0 | 截图可见字段未增加 |

### 判断

- 输入采集/发布约 **59.8 fps**，接近 60 fps。
- 算法每秒完成并发布约 **29.1 帧**；显示端每秒只取到约 **29.1 张新输出帧**。因此这次测到的有效算法输出约为 29 fps，未达到 60 fps。
- 61 秒内少处理的 1,872 帧恰好等于 `capture_dropped_count` 的增量；目前瓶颈在处理吞吐，输入端大约每两帧才有一帧进入输出。输出丢弃和 `copy_error_count` 在截图可见读数中没有增加。
- HDMI 时序仍可能是 60 Hz，显示器也会继续刷新并重复显示最近一张输出帧；这不代表算法产生了 60 张不同的新帧。屏幕连续画面看起来完整，与约 29 fps 的新帧率并不矛盾。
- 截图只显示到部分 DebugCore 通道；未出现在可见区域的错误计数仍为**未观测**，不能记作零。两个计数器增量以 61 秒作为时间基准，结果有约 1.6% 的时间取整不确定度。

## 后续

先针对处理路径做吞吐优化，再重复同一套 60 秒硬件测量。仿真中的全帧理想 DDR 模型约 14.77 ms/帧（约 67.7 fps），但实板约 29.1 fps，差距提示并发 DDR 争用、读访问效率或处理等待需要进一步定位。当前数据已足以确认“不满足 60 fps”，但不足以单独判定上述哪一项是主因。优化后还需检查运动帧号、所有错误计数以及长时间稳定性。

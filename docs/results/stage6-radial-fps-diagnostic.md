# Stage 6 Brown-Conrady 帧率诊断

_2026-10-22；工程 `fpga/project/stage6_radial_fps_debug/`。_

诊断工程与[普通显示工程](stage6-radial-ddr.md)使用相同固定试值：`k1=-0.25`、`k2=+0.0625`、`p1=+0.03125`、`p2=-0.03125`，坐标以 `(640,360)` 为中心并除以 512 归一化。它接入 256 通道 Fabric DebugCore，测量真实 HDMI 输入经 DDR 图块缓存、映射与插值后的帧处理吞吐。

## 构建与文件

- [诊断 `.sbit`](../../fpga/project/stage6_radial_fps_debug/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit)
- [匹配的 `.fic`](../../fpga/project/stage6_radial_fps_debug/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic)

PDS 2022.2-SP6.4 全流程通过，后布局报告 `All Constraints Met`；DDR 125 MHz 域建立裕量 +0.322 ns。诊断 `.sbit` 大小 9,188,552 字节，SHA-256 `102126244AFDBB2477A0A914A040A4E6981DA7FA564EAADD8326BDD6E65ABB9A`；配套 `.fic` 大小 22,137 字节，SHA-256 `92B24916F447ACAFB7CF149AC7C3B04BFD3CBFDE0CA6BFCCBAE944FF5BF362B7`。`.sbit` 与 `.fic` 必须来自本工程同次构建；旧 `k1=+0.25` 的诊断位流不能代表当前映射的帧率。

## 测量

1. 输入源设为 1280×720、60 Hz，播放带变化帧号的画面。
2. 烧录本工程 `.sbit`，在 Fabric Debugger 导入匹配 `.fic`，连接 `CORE:0 MyFLA0`。
3. 使用 **Trigger Immediate** 捕获两次 Listing，间隔约 60 秒并记录 Console 实际时间。
4. 用输入发布、`copied_count` 和显示取新帧计数的增量除以间隔秒数，并记录丢帧和错误计数。

通道定义见[工程 JTAG 说明](../../fpga/project/stage6_radial_fps_debug/README_JTAG.md)。

## 实板读数（2026-10-23）

Debugger Console 时间为 08:32:14 和 08:33:15，间隔 61 秒。取两张 Listing 的首行：

| 计数器 | 第一次 | 第二次 | 增量 | 帧率 |
|---|---:|---:|---:|---:|
| 输入发布 `input_published_count` | `0x0011d5` | `0x001ffc` | 3,623 | 59.39 fps |
| 处理完成 `copied_count` | `0x00000664` | `0x00000b76` | 1,298 | 21.28 fps |
| 显示取帧 `display_take_count` | `0x00000664` | `0x00000b76` | 1,298 | 21.28 fps |
| 输入丢帧 `capture_dropped_count` | `0x0b70` | `0x1484` | 2,324 | 38.10 帧/秒 |

`copy_error_count` 两次均为 0，`output_dropped_count` 两次均为 0。当前这组未标定 Brown-Conrady 试值下，输入约 59.4 fps，实际处理并显示约 **21.3 fps**；瓶颈表现为输入帧没有全部进入处理链路，记录到约 2,324 帧输入丢弃。该读数对应当前诊断位流和当前画面，不代表标定后的最终参数性能。

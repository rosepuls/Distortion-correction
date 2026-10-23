# Stage 6 Brown-Conrady 帧率诊断

_2026-10-22；工程 `fpga/project/stage6_radial_fps_debug/`。_

诊断工程与[普通显示工程](stage6-radial-ddr.md)使用相同固定试值：`k1=-0.25`、`k2=+0.0625`、`p1=+0.03125`、`p2=-0.03125`，坐标以 `(640,360)` 为中心并除以 512 归一化。它接入 256 通道 Fabric DebugCore，测量真实 HDMI 输入经 DDR 图块缓存、映射与插值后的帧处理吞吐。

## 构建与文件

- [诊断 `.sbit`](../../fpga/project/stage6_radial_fps_debug/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit)
- [匹配的 `.fic`](../../fpga/project/stage6_radial_fps_debug/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic)

PDS 2022.2-SP6.4 全流程通过，后布局报告 `All Constraints Met`。当前链接指向 **2026-10-23 性能分解版本**：`.sbit` 大小 9,188,552 字节，SHA-256 `C4D7AD90BB9F5BEFD38090E1468A775C74544BA978DACA5AA5EAA17F0D37E7AD`；配套 `.fic` 大小 22,577 字节，SHA-256 `18CD6BD243D5BC81B700B06D771091A974696DD310AB30FFE24365F9F5535D23`。旧帧率版本保存在 `generate_bitstream/baseline_fps/`，其 `.sbit` SHA-256 为 `102126244AFDBB2477A0A914A040A4E6981DA7FA564EAADD8326BDD6E65ABB9A`，`.fic` SHA-256 为 `92B24916F447ACAFB7CF149AC7C3B04BFD3CBFDE0CA6BFCCBAE944FF5BF362B7`。两组文件分别配对使用；旧 `k1=+0.25` 的诊断位流不能代表当前映射的帧率。

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

## 性能分解实板读数（2026-10-23）

烧录上面的性能分解位流，Fabric Debugger Console 时间为 10:06:28 和 10:07:28，间隔 60 秒。两次 Listing 的首行如下；前四列是累计计数，后七列是最近完成帧的快照，不能对快照求时间差。

| 累计计数器 | 开始 | 结束 | 60 秒增量 | 速率 |
|---|---:|---:|---:|---:|
| 输入发布 | `0x5c20` | `0x6a30` | 3,600 | 60.00 fps |
| 处理完成 | `0x2103` | `0x260c` | 1,289 | 21.48 fps |
| 显示取新帧 | `0x2102` | `0x260c` | 1,290 | 21.50 fps |
| 输入丢弃 | `0x3b1c` | `0x4422` | 2,310 | 38.50 帧/秒 |

| 最近完成帧计数器 | 开始截图 | 结束截图 | 对帧周期的约略占比 |
|---|---:|---:|---:|
| 总周期 | `0x58d152` (5,820,754) | `0x5887ba` (5,801,914) | 100% |
| 坐标反压 | `0x461a9d` (4,594,333) | `0x45f9ab` (4,585,899) | 79% |
| Tile 填充次数 | `0x005e76` (24,182) | `0x005e76` (24,182) | 次数，非周期 |
| Tile 填充与重试周期 | `0x44bdf2` (4,505,074) | `0x448a44` (4,491,844) | 77% |
| 读 AR 等待 | `0x089f17` (565,015) | `0x08974e` (563,022) | 9.7% |
| 读响应等待 | `0x2b17dd` (2,824,157) | `0x2aebf8` (2,812,920) | 48.5% |
| 写 AW/W 反压 | `0x02c7cd` (182,221) | `0x029f2f` (171,823) | 约 3% |

两次 `perf_error_flags` 都是 `0x0000`。计数器存在重叠：缓存填充期间坐标输入通常也被反压；不能把各项占比相加。按 125 MHz 估计，单帧约 46.5 ms；60 fps 的预算约 2.08 百万周期。缓存填充和 DDR 读等待是当前优先优化的路径。下一轮实验使用独立 Stage 7 工程，见[吞吐率优化计划](../plan/2026-10-23-stage6-throughput-optimization.md)。

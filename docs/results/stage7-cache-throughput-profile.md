# Stage 7 缓存吞吐率候选：16 组 × 8 路

## 改动范围

独立工程：`fpga/project/stage7_cache_profile_32x8/`，另有布线备选 `fpga/project/stage7_cache_profile_16x8/`。两者从当前 Stage 6 性能诊断工程复制项目输入，保持 Brown-Conrady 固定试值、DDR/帧槽控制和 256 通道 FIC 映射。唯一的数据通路参数变更是在 `fram_buf.v` 中扩展 tile 缓存。tile 仍为 32 × 4 像素；32 × 8 像素存储为 128 KiB，16 × 8 为 64 KiB，Stage 6 基线为 32 KiB。

## 可重现的离线分析

命令：

```powershell
$env:VIVADO_HOME = 'D:\Xilinx\Vivado\2020.2'
& ./fpga/sim/Run-Stage7CacheReplay.ps1
& ./fpga/sim/Run-Stage7FullPipelineProfile.ps1 -CacheSets 16 -CacheWays 4 -ReadDelay 30 -WritePause 17
& ./fpga/sim/Run-Stage7FullPipelineProfile.ps1 -CacheSets 32 -CacheWays 8 -ReadDelay 30 -WritePause 17
& ./fpga/sim/Run-Stage6RadialPipeline.ps1 -CacheSets 32 -CacheWays 8
```

坐标来自完整 1280 × 720 固定点 RTL 映射与双线性取样规划。缓存模型使用当前 RTL 的 set 函数、四邻域访问顺序和精确 LRU。输出位于忽略目录 `fpga/sim/.work/stage7-cache-replay/`。

| 组 × 路 | 像素容量 | 离线填充次数/帧 | 相对 16 × 4 减少 |
|---|---:|---:|---:|
| 16 × 4 | 32 KiB | 21,645 | 基线 |
| 16 × 8 | 64 KiB | 8,229 | 61.98% |
| 32 × 4 | 64 KiB | 13,083 | 39.56% |
| 32 × 8 | 128 KiB | 6,132 | 71.67% |

16 × 4 的实际缓存 RTL 回放和完整处理流水仿真均为 21,645 次；16 × 8 与 32 × 8 的完整处理流水仿真分别为 8,229 和 6,132 次。完整帧仿真使用理想化单笔 DDR 行返回模型，延时设为 30 周期，并在每 128 个输出像素后施加 17 周期暂停；结果为 16 × 4 处理 4,785,820 周期、16 × 8 处理 2,573,420 周期、32 × 8 处理 2,227,278 周期。这些周期不等同于实板处理时间；在 125 MHz 下，16 × 8 和 32 × 8 的此模型结果仍高于 60 fps 的 2,083,333 周期预算。

16 × 8 和 32 × 8 配置下，原有 Brown 流水抽样仿真均通过，检查了中心、内部和边界像素以及帧/像素元数据；完整帧仿真检查了 921,600 个输出像素的顺序和读错误状态。完整帧仿真的 DDR 数据为零，因而并未逐像素比较整帧图像内容。

综合阶段资源：Stage 6 基线使用 DRM 18/415、LUT 15,435/159,800；Stage 7 16 × 8 使用 DRM 26/415、LUT 21,893/159,800；Stage 7 32 × 8 使用 DRM 42/415、LUT 34,691/159,800。布局布线后的资源与时序以各工程的最终报告为准。

16 × 8 已完成布局布线：DRM 30/415；正式时序报告为 `All Constraints Met`，`ddrphy_sysclk` 125 MHz 域最差建立裕量 +0.165 ns。位流生成成功，文件为 `fpga/project/stage7_cache_profile_16x8/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`，SHA-256 `D9F63FD8B33D4245B373A8E52F802744E25C1B4880D92422A4BB41730C489F20`；同次构建 FIC 为同目录 `HDMI_IN_DDR3_HDMI_OUT_top.fic`，SHA-256 `6E85A21D13AEB7E687DC6C1798A3561D36EC57553750ED04921BE81A43EAE58D`。

32 × 8 在布线第 78 轮仍有 4,602 条连接未布通，且详细布局结束的最差裕量为 −0.786 ns。本次构建已中止；没有可用的 32 × 8 位流或最终时序结论。保留工程与日志供后续优化缓存结构时使用。

## Stage 7 实板采样

Fabric Debugger 控制台时间为 13:37:05 和 13:38:05，间隔 60 秒。截图中计数如下：

| 信号 | 开始 | 结束 | 增量/快照 |
|---|---:|---:|---:|
| 输入发布计数 | `0x2527` | `0x3346` | 3,615（60.25 fps） |
| 处理完成计数 | `0x134a` | `0x1a9f` | 1,877（31.28 fps） |
| 显示取新帧计数 | `0x134a` | `0x1a9f` | 1,877（31.28 fps） |
| 输入丢帧计数 | `0x11db` | `0x18a5` | 1,738（28.97 fps） |
| 错误标志 | `0x0000` | `0x0000` | 无错误 |
| 最近完成帧周期 | `0x3d3cb7` | `0x3d2cc1` | 4,013,239 / 4,009,153 周期 |
| 最近完成帧缓存填充数 | `0x003809` | `0x003809` | 14,345 次/帧 |

输入、处理和丢帧增量满足 `3,615 = 1,877 + 1,738`。处理完成帧率相对 Stage 6 的 21.48 fps 提升约 45.6%，但仍有约 28.97 fps 输入未被处理；距离 60 fps 目标还有明显差距。按最新帧周期除以 125 MHz 得到约 31.18 fps，与 60 秒计数得到的 31.28 fps 接近。

两次快照都是独立的最近帧计数器，cache miss 并非累加计数。Stage 7 实板 14,345 次/帧，较 Stage 6 实板 24,182 次/帧减少约 40.7%；离线 16×8 模型预测 8,229 次/帧，低于实测，模型差异仍未解释。截图不显示烧录文件名，因此此段实板结论以确实烧录本文件记录的 16×8 `.sbit/.fic` 配对为前提。

## 与实板 Stage 6 基线的差异

2026-10-23 的 Stage 6 JTAG 读数为每完成帧 24,182 次 tile 填充，较同参数完整帧仿真多 2,537 次。当前尚未定位差异；因此离线模型只用于候选排序，不据此宣称 Stage 7 的实板未命中数或帧率。需要使用同一输入源和约 60 秒间隔的 Stage 7 JTAG 快照核验。

## 构建与上板复测

生成 16 × 8 工程：`./fpga/project/New-Stage7CacheProfile.ps1 -ProjectDirectory ./fpga/project/stage7_cache_profile_16x8 -CacheSets 16 -CacheWays 8`。构建：`./fpga/project/Run-Stage7CacheProfile.ps1 -ProjectDirectory ./fpga/project/stage7_cache_profile_16x8`。本次构建的 `.sbit` 与匹配 `.fic` 已在 `fpga/project/stage7_cache_profile_16x8/generate_bitstream/`。上板时按工程内 `README_JTAG.md` 导入配套文件并采集通道。

复测记录输入发布、处理完成、显示取帧、输入丢帧的 60 秒增量，以及最近完成帧的 `perf_frame_cycles`、`perf_cache_miss_count`、`perf_cache_fill_cycles`、DDR 读等待和 `perf_error_flags`。对照 Stage 6 的 21.48 处理帧/秒、约 580 万周期/帧、24,182 次填充/帧、零错误标志。检查显示画面是否完整、颜色是否正确。

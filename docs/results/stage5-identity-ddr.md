# Stage 5：真实 DDR 帧的单位映射验证

_2026-10-22；PG2L200H；独立工程 `fpga/project/stage5_identity_ddr/`。_

## 目标和数据路径

在 Stage 3 CDC 修复版的摄像头采集、双帧池所有权、DDR 读写仲裁和 HDMI 显示路径之间，替换处理侧的直接帧复制：

```text
已完成输入槽 0..2
  -> 单位 Q16.16 坐标 + 坐标 FIFO
  -> 四邻点规划 + DDR 图块行读取 + Tile Cache
  -> 三级双线性插值
  -> 16 拍输出写突发 -> 输出槽 3..5
  -> 写事务排空 -> 帧池发布 -> HDMI
```

这一版必须先让输出与输入逐像素一致，再引入径向映射和标定参数。RGBX8888 的低字节按现有算法约定写零，因此一致性比较使用 RGB 高 24 位。

`tile_row_ddr_adapter.sv` 把 32 像素图块行读转换为 4 拍、每拍 256 位的 DDR 突发，发命令前预留完整返回空间。`pixel_tile_cache.sv` 取自旧仓库 `Pango_Micro_FPGA_Old/Distortion-correction/rtl/platform/common/memory/`，保持缓存逻辑原样；设备专用的旧 bank RAM 包装器由 `tile_cache_bank_ram.sv` 的 PG2L200H 可综合推断 RAM 替换。输入槽切换时缓存失效。处理引擎只在 921,600 个像素都写入且输出写事务排空后发送 `copy_done`；故障时锁住处理并要求复位，避免发布部分输出帧。

## 已完成的仿真

| 脚本 | 检查范围 |
| --- | --- |
| `fpga/sim/Run-TileRowDdrAdapter.ps1` | 输入槽地址、4 拍突发、AR 等待、返回缓存、错误 RLAST |
| `fpga/sim/Run-CachedNeighborReader.ps1` | 跨图块邻域、边缘夹紧、反压、输入槽切换与缓存失效 |
| `fpga/sim/Run-PipelinedBilinearInterpolator.ps1` | 100 组随机 RGB/权重/掩码与原插值器位精确一致，输出反压 |
| `fpga/sim/Run-Stage5IdentityPipeline.ps1` | 两帧共 1,024 个有序像素、元数据和帧槽切换 |
| `fpga/sim/Run-FrameIdentityTransformEngine.ps1` | 两帧 DDR 模型输入/输出、16 拍写突发、写排空和完成序号 |
| `fpga/sim/Run-FrameIdentityTransformEngine.ps1 -FullFrame` | 1280×720 全帧 921,600 个像素、7,200 个输出突发及末帧排空 |

全帧模型以 125 MHz 时钟完成一次处理用了 **1,846,598 周期，约 14.77 ms**；读出 50,980 个图块行，写出 7,200 个 16 拍突发。60 帧每秒窗口为约 2,083,333 周期，理想模型只剩约 236,735 周期（1.89 ms）供额外争用和等待。该模型读请求立即被接受，且没有并发采集和显示，因此不能据此确认实板能持续 720p60。

## PDS 时序记录

初版单周期插值器综合通过，使用约 14,176 LUT（8.87%）和 17 个 DRM36K 等效块（4.10%），但 125 MHz DDR 域后布线最差建立时间裕量为 **−2.869 ns**。失败路径从 Tile Cache 读指针经过像素选择、水平和垂直乘法，直到插值输出寄存器。该初版位流不用于上板。

改用三级弹性流水后，第二次 PDS 全流程完成，报告 `All Constraints Met`。125 MHz DDR 域最差建立裕量 **+0.538 ns**，74.2501 MHz 输出域裕量 **+6.700 ns**；综合资源为 14,567 LUT（9.12%）和 17 个 DRM36K 等效块（4.10%）。布线后网表再次看到显示消费 Gray 指针的寄存器输出直接进入 DDR 第一同步级，随后直接进入第二同步级；最高位与同值的二进制寄存器共享，不经过组合逻辑。尚未重新计算跨域路径的慢角延迟界限。

可上板候选位流：[`HDMI_IN_DDR3_HDMI_OUT_top.sbit`](../../fpga/project/stage5_identity_ddr/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit)，大小 9,188,552 字节，SHA-256：`06A0B9B33B0A5C4FEE63DE2F9A595D1B743D85ED370EBA699BBEB69C73E5F714`。这是**时序通过、尚未实板验证**的候选版本。

## 上板检查

烧录上述 Stage 5 位流并保留 Stage 3 CDC 修复版作对照。先用静态彩条或棋盘格检查颜色、行列方向、边缘和帧完整性，再用带帧号运动画面观察卡顿或跳帧。LED4 表示显示适配器错误或处理引擎故障，LED5 表示读仲裁错误，LED6 表示显示门控有效，LED7 表示曾输出非零 RGB；LED0 仍为心跳。期望正常有画面时 LED4/5 灭、LED6/7 亮。

2026-10-22 用户烧录上述候选位流后反馈：LED4、LED5 常暗，LED6、LED7 等其余灯亮，LED0 闪烁；[静态桌面图](stage5-identity-board-static-2026-10-22.png)完整。图中未见明显错行或大片缺失。后续用独立诊断位流实测：输入发布 **59.80 fps**，算法完成/显示取得新帧 **29.11 fps**，输入帧丢弃约 **30.69 帧/s**；因此当前处理吞吐尚未达到 720p60。详见[帧率诊断记录](stage5-fps-diagnostic.md)。

下一步使用独立 [`stage5_identity_fps_debug`](stage5-fps-diagnostic.md) 工程的配套 `.sbit`/`.fic` 经 Pango Fabric Debugger 读取输入发布、算法完成和显示取帧计数，两次读数相隔约 60 秒；运动图测试连续运行 30 分钟。处理帧、丢帧和缓存行读取计数未接到普通 Stage 5 位流的板载 LED，不能仅凭 LED 判断 720p60 持续吞吐。

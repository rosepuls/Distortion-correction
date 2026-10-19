# 盘古 200Pro+ 720p60 畸变矫正

目标板卡为 PG2L200H。实施顺序见 [项目计划](docs/plan/2026-10-19-720p60-distortion-correction.md)。阶段 1 的 HDMI 直通已由用户在板上完成；当前进行阶段 2 的 DDR3 视频缓存。

## 工程目录

| 目录 | 用途 |
| --- | --- |
| `fpga/project/` | PDS 工程生成脚本及本地工作工程 |
| `fpga/rtl/video/` | HDMI 视频链路与 720p60 时序 |
| `fpga/rtl/memory/` | DDR3 帧槽、读取与缓存 |
| `fpga/rtl/correction/` | 坐标映射与双线性插值 |
| `fpga/rtl/control/` | 参数寄存器及 UART 控制 |
| `fpga/constraints/` | 管脚及时钟约束增量 |
| `host/calibration/` | 相机标定和参数导出 |
| `host/reference/` | OpenCV 参考图与比较 |
| `sim/` | RTL 仿真输入与脚本 |
| `docs/results/` | 板上实测与验收记录 |

这些目录先固定接口边界；后续代码按计划逐步加入。

## 阶段 1：HDMI 直通

从仓库根目录运行：

```powershell
powershell -NoProfile -File .\fpga\project\New-Stage1Project.ps1
```

脚本在 `fpga/project/stage1_hdmi_loop/` 生成本地 PDS 工程，并把 `fpga/edid/720p60.hex` 应用到 MS7200 配置表。用 PDS 打开其中的 `hdmi_loop.pds`，检查器件为 `PG2L200H / FBB676 / -6`。当前本机已生成 `generate_bitstream/hdmi_loop.sbit`；下载前请按现场板卡再次核对管脚和供电。电脑 HDMI 输出设置为 `1280×720@60 Hz`，并在高级显示器设置中核对**活动信号模式**也是 1280×720@60 Hz。这个阶段由输入像素时钟直接驱动输出，因此不需要输出 74.25 MHz PLL；配置 PLL 只用于 HDMI 收发芯片的 I²C 初始化。

本地工程需要与本仓库同级的 `盘古200Pro+开发板配套资料`。厂商源码、管脚约束和 IP 只复制到被忽略的本地工作工程；提交源码时先核对再分发许可。生成脚本发现目标目录已存在时会停止，防止覆盖 PDS 中的本地修改。已有工程要更新 EDID 时，运行 `fpga/project/Set-Stage1Edid.ps1`，再重新构建位流。

阶段 1 必须在硬件上确认显示器锁定 720p60、画面无错色或裁切，并分别记录 UVC 实际帧率和 HDMI 刷新率。当前时序报告仅覆盖内部时钟路径；片外 RGB/同步接口的输入、输出延迟仍需结合芯片时序补齐。构建结果和硬件记录模板见 `docs/results/stage1-hdmi-loop.md`。

## 阶段 2：DDR3 视频缓存基线

从仓库根目录运行：

```powershell
powershell -NoProfile -File .\fpga\project\New-Stage2Project.ps1
```

脚本从 PG2L200H 厂商 `4_10_timing` 工程生成被 Git 忽略的 `fpga/project/stage2_ddr3_720p60/`，并统一设置仅支持 720p60 的 EDID、74.25 MHz 输出 PLL、1280×720 缓冲尺寸、1650×750 输出时序与 74.25 MHz 输入时钟约束。PDS 文件为 `HDMI_IN_DDR3_HDMI_OUT.pds`。这是厂商 **RGB565 双帧缓存**的 720p60 初始基线；已验证稳定的末行修正版以及新增帧槽/RGBX 工程见下文。

厂商缓冲以 32 位 DDR 地址计数：RGB565 每帧占 460,800 个字，当前帧槽起点间隔 2²² 个字，不会互相覆盖。厂商 RAM IP 元数据有 PG2L100H/FBG484 警告，构建和硬件表现须单独核查，不能将该警告视为已解决。阶段 2 的硬件记录见 `docs/results/stage2-ddr3-baseline.md`。

曾尝试运行 `fpga/project/Add-Stage2Diagnostics.ps1` 给 LED4–7 加入锁存诊断，但该诊断位流在板上导致明显画面回退；当前应使用无诊断逻辑的基线位流。故障经过见阶段 2 记录。

回退用的独立基线工程位于 `fpga/project/stage2_ddr3_720p60_baseline_restore/`，其位流为 `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`。此工程从厂商源文件重新生成，没有 LED4–7 诊断逻辑。

排查偶发错位闪屏的单变量对照工程可由 `fpga/project/New-Stage2SharedClockProject.ps1` 生成，位流位于 `fpga/project/stage2_ddr3_720p60_shared_clock/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`。它让 HDMI 输出共用输入像素时钟；用户上板反馈闪屏更快，故不要将其作为稳定版本。实验说明见 `docs/results/stage2-ddr3-baseline.md`。

恢复版画面底边的黑色缺口对应 `rd_buf` 少预取第 720 行。`fpga/project/New-Stage2LastLineProject.ps1` 生成只修正该计数条件的独立工程，位流位于 `fpga/project/stage2_ddr3_720p60_last_line/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`；用户上板连续运行至少 30 分钟，未复现黑边或错位。调试压缩记录见 `docs/chat/2026-10-19-720p60-ddr3-debug-summary.md`。

在此已验证版本基础上，`New-Stage2FrameSlotProject.ps1` 生成 RGB565 三帧槽交接和错误计数工程，`New-Stage2RgbxProject.ps1` 生成 RGBX8888 三帧槽工程。RGBX8888 的 PDS 工程、RTL、IP 源码和构建脚本已提交到 `fpga/project/stage2_ddr3_720p60_rgbx8888/`；克隆后可直接打开该工程重新生成位流。两个版本均已由 PDS 生成位流；用户反馈 RGB565 三槽版快速闪屏，RGBX8888 三槽版目前显示正常。具体观察和 LED4–7 含义见 `docs/results/stage2-frame-handoff-rgbx.md`；已完成 30 分钟稳定性验证的回退位流仍是末行修正版。

## 阶段 3：相机标定准备

当前尚无真实工业相机标定照片。[上位机说明](host/README.md)提供 A4 棋盘格、原始 720p 照片采集要求、OpenCV 标定、软件参考图和定点参数导出命令。脚本不生成虚构内参；收到真实照片后才能完成本阶段数据分析。

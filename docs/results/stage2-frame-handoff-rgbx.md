# 阶段 2：帧槽交接与 RGBX8888

日期：2026-10-19。板卡：盘古 200Pro+ / PG2L200H。已验证回退位流仍是 `stage2_ddr3_720p60_last_line`，其 RGB565 画面已连续稳定运行至少 30 分钟。

## 生成与构建

在仓库根目录先后运行：

```powershell
powershell -NoProfile -File .\fpga\project\New-Stage2FrameSlotProject.ps1
powershell -NoProfile -File .\fpga\project\New-Stage2RgbxProject.ps1
```

两个脚本从本地厂商例程重新生成独立 PDS 工程，均保留 720p60 EDID、74.25 MHz 输出 PLL 与第 720 行预取修正。RGB565 三槽工程位于 `fpga/project/stage2_ddr3_720p60_frame_slots/`；RGBX8888 工程的 PDS、RTL、IP 源码和构建脚本已提交到 `fpga/project/stage2_ddr3_720p60_rgbx8888/`。克隆仓库后可直接打开 RGBX8888 PDS 工程构建；生成目录和位流仍由 `.gitignore` 排除。生成脚本不会覆盖已有目录。

| 版本 | 像素布局 | 每行 DDR 32 位字数 | 每帧字数 | 槽跨度 |
| --- | --- | ---: | ---: | ---: |
| 帧槽 RGB565 | `{R[7:3],G[7:2],B[7:3]}` | 640 | 460800 | 2²² 字 |
| 帧槽 RGBX8888 | `{R,G,B,8'h00}` | 1280 | 921600 | 2²² 字 |

两版均由 DDR 时钟域的 `frame_slot_manager` 负责三个槽的所有权。输入 VS 只发布写满 720 行且写命令空闲的槽；输出 VS 只读已发布完整槽。显示读取未完成时保持旧槽并计数，不释放给写端。输入/输出 VS 同周期时，显示端使用此前已发布的帧。复位到首帧完成前输出黑色。

错误计数为 16 位饱和寄存器，另保留 32 位发布/显示帧序号及重复显示帧计数。PDS 调试标记保留这些内部信号，后续可接 UART 遥测。LED0–3 保持心跳、DDR 初始化和 HDMI 初始化的原用途；LED4–7 为以下计数非零后的锁存摘要，复位清零：

| 灯 | DDR 域计数 |
| --- | --- |
| LED4 | 输入帧不完整 |
| LED5 | 显示帧读取不完整 |
| LED6 | 写行请求到达时命令端忙 |
| LED7 | 读行请求到达时命令端忙 |

重复显示帧单独计数，不直接点亮错误灯；输入和输出的独立像素时钟可使重复帧出现。计数不能代替画面检查，后续 UART 状态接口需要再定义。

## 工具链结果

| 项目 | RGB565 三槽 | RGBX8888 三槽 |
| --- | --- | --- |
| PDS 2022.2-SP6.4 位流 | 已生成，见本地 `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit` | 已生成，见本地 `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit` |
| 位流 SHA-256 | `E978E2F73A57C2AE11C5128ED8816DF0878ABFF5FABF47ACB6AAF3332328975C` | `7D2786B57DEE93528C6B29B26CEFD10B5D68EF0AAAE6B51D8796483CFA9CDC37` |
| 内部时序 | `All Constraints Met`；DDR 域 WNS 2.199 ns、输入像素域 8.947 ns | `All Constraints Met`；DDR 域 WNS 1.760 ns、输入像素域 7.845 ns |
| 板上画面与 LED | 用户反馈画面快速闪屏，底部无黑边；LED4–7 状态尚未记录 | 用户反馈画面正常；LED4–7 状态及颜色测试图尚未记录 |
| 30 分钟稳定运行 | 用户反馈快速闪屏，未通过 | 尚未完成 |

厂商行 RAM IP 元数据仍标称 PG2L100H，PDS 会警告；两工程沿用此前在 PG2L200H 上可工作的同一 IP。HDMI 输入输出片外延迟约束仍待补齐，内部 `All Constraints Met` 不能替代上板验证。

## 上板顺序

1. **RGB565 三槽版暂不使用。** 用户上板后观察到快速闪屏，但末行无黑边。该结果不能单独证明帧槽管理器有问题；与 RGBX8888 版的像素宽度、DDR 吞吐和布局布线均不同，原因仍待定位。
2. 目前继续使用显示正常的 **RGBX8888 三槽版**。显示红、绿、蓝、白纯色及交替色竖条，检查通道与像素顺序；观察任务栏底边和运动画面，连续运行至少 30 分钟，并记录 LED4–7。用户目前只反馈“画面正常”，尚未完成完整稳定性验收。
3. RGBX8888 版若出现错位、黑边、错色或异常 LED，回退已验证的 `stage2_ddr3_720p60_last_line`，保留现场照片、异常出现时间及对应位流版本。

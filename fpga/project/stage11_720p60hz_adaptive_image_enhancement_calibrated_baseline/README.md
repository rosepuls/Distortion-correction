# Stage 11 720p60Hz 自适应图像增强测试工程（K3 基线）

## 5 号标定参数对照副本（2026-10-30）

本工程从已验证稳定的 `stage11_curve1to4_refit_test` 复制。0–4 号保持稳定版本，5 号使用标定候选 `gamma=0.65, knee=120, power=2.80`。相对源副本，RTL ROM 只改变 LUT 5。构建位流用于检查只改变 5 号表后，无 UART 参数时输出是否抖动。

本副本已于 2026-10-30 完成 PDS 综合、布局布线和位流生成；41969 条网络全部布通。时序报告为 `All Constraints Met`，慢角 `ddrphy_sysclk` setup WNS `+0.085 ns`、TNS 0、失败端点 0。位流为 `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`（9,188,552 字节，SHA-256 `25C6443F854D484E3EE427C7DBB3BCA2D2E4E855C3E6EC54853951EDF566549D`）。此位流尚待板上观察确认画面是否抖动；时序报告不能替代实测。

## 1–4 号曲线样本拟合副本（2026-10-30）

本目录是从 `stage11_720p60hz_adaptive_image_enhancement_test` 完整复制出的独立工程。相对旧工程只改了 `source/rtl/correction/lighting_lut_rom.sv` 中 LUT 1–4；LUT 0、5 和 `impl.tcl` 保持原样。拟合参数快照位于本目录 `lighting_curve_parameters.json`，对应样本统计与曲线对照位于仓库的 `../../../host/pose/output/lighting_curve_refit_20261030/`。

| 曲线 | 参数 |
|---|---|
| 0 旁路 | `identity`，保持未处理参考画面 |
| 1 夜间 | `gamma=0.61` |
| 2 强夜间 | `gamma=0.41` |
| 3 高光 | `knee=108, power=1.45` |
| 4 强高光 | `knee=88, power=2.15` |

0 号用 15 张正常光照样本核对旁路：输入平均亮度中位数 `159.38`，输出不变且 RGB 平均绝对变化为 0，因此保持 identity，不把参考曲线拟合成色调变换。1–4 号参数按每类 15 张 1280×720 样本拟合并在原分辨率复核，属于离线候选。拟合指标见 `../../../host/pose/output/lighting_curve_refit_20261030/`。

本副本已经完成 PDS 综合、布局布线和位流生成。布线后 `All Constraints Met`，`ddrphy_sysclk` setup WNS `+0.182 ns`、TNS 0、失败端点 0。`.sbit` 与配套 `.fic` 位于 `generate_bitstream/`；烧录后仍需实测无 UART 参数时 0 号旁路画面是否抖动，静态时序报告不能代替板上验证。

PDS 仍提示若干 HDMI/DDR/UART I/O 没有外部时序约束，并提示两个 DDR FIFO IP 的器件信息为 PG2L100H、当前工程目标为 PG2L200H。`All Constraints Met` 仅覆盖已约束路径。

本工程由 `stage8_720p60hz_bilinear_uart_angle_correction_65byte_k3_test` 完整复制而来，作为 Stage 11 自适应图像增强的独立开发起点。保留 720p（1280×720）视频链路、双线性插值、UART 参数接收、单应角度校正和已标定 K3。本项目改动不会影响原 Stage 8 K3 基准。

## Stage 11 图像增强接口与当前实现

曲线编号使用现有版本 `02`、65 字节 UART 帧的偏移 43，合法范围 `0–5`；偏移 44–62 保持全零，CRC 继续覆盖偏移 2–62。编号、单应矩阵和 pose-valid 标志作为同一 pending 参数组，并在输出帧边界原子切换。复位曲线为 `0:bypass`。越界曲线编号返回状态 `07`，非零保留字节返回 `06`。接口详见 [`stage11-adaptive-image-enhancement-interface.md`](../../../docs/plan/stage11-adaptive-image-enhancement-interface.md)。

当前 Stage11 RTL 已解析偏移 43 的曲线编号，并在双线性插值之后、输出 DDR 写入之前对 RGB 三通道应用同一条 LUT；RGBX 低字节保持原样。曲线 ID 与单应矩阵在同一帧边界生效。Stage11 本次构建位流支持非零曲线编号；Stage8 K3 位流仍要求偏移 43–62 全零。

初始曲线参数位于 `host/pose/lighting_curve_parameters.json`。运行 `python host/pose/generate_lighting_lut_rom.py` 可更新 Stage11 ROM；运行 `python host/pose/compare_lighting_curves.py` 可重新生成离线 LUT、指标和样本对照。当前参数是可调候选，不是最终画质参数；后续重拍后改该 JSON 并重新生成即可保持 UART 和像素接口不变。

## 串口接口

- 板卡：盘古 200Pro+（PG2L200H-6-FBB676）
- USB-UART：115200 baud、8-N-1、无流控
- FPGA RX：B24；FPGA TX：C24
- 板载 LED3（FPGA 引脚 E18）：每接收完一帧请求翻转一次，包括接受和拒绝的请求
- HDMI 仍保持原视频链路；参数只在下一个接受的输出帧开始处原子生效

## 参数帧

请求和响应均为固定 65 字节。协议版本为 `02`。串口工具使用十六进制发送，关闭自动重发，并一次只发送一帧，收到完整响应后再发送下一帧。

| 偏移 | 长度 | 请求 | 响应 |
|---:|---:|---|---|
| 0 | 2 | `A5 5A` | `A5 5A` |
| 2 | 1 | 协议版本 `02` | `02` |
| 3 | 1 | 请求类型 `01` | 响应类型 `81` |
| 4 | 2 | 小端序号，同时作为参数版本 | 回显序号 |
| 6 | 1 | flags：bit 0 为 pose_valid，bit 7:1 必须为 0 | 状态码，`00` 表示接受 |
| 7 | 36 | 9 个 row-major 的小端 32 位单应系数 | 回显系数 |
| 43 | 1 | 增强曲线编号 `0–5` | 原样回显 |
| 44 | 19 | 保留，必须全为 `00` | 原样回显 |
| 63 | 2 | CRC 高字节在前 | CRC 高字节在前 |

系数顺序为 `h00,h01,h02,h10,h11,h12,h20,h21,h22`。前两行是有符号 Q16.16，末行是有符号 Q2.30；`h22` 必须为 `0x40000000`。编号 0 为 bypass，1/2 为暗部提亮，3/4 为高光压缩，5 为混合曲线；44–62 非零时返回 `06`，曲线编号超出 0–5 时返回 `07`。CRC 为 CRC-16/CCITT-FALSE（poly `0x1021`、init `0xFFFF`、无反射、xorout `0`），覆盖偏移 2 至 62。解析器还检查协议字段、标志和 1280×720 四角坐标范围。无效、残缺、CRC 错误或超范围数据不更新参数。

接受的数据先进入 pending 参数组；视频处理引擎在下一帧边界将它切换为 active 参数。映射器把输出坐标映射到源图坐标，因此 `h02=+16 px` 会让输出从输入图像右侧多取 16 像素，画面内容相对左移。首个合法角度包可用该平移确认参数确实经过 UART、参数 bank 和坐标映射链路。

## 生成测试帧

默认生成单位矩阵请求：

```powershell
.\sim\Build-UartPacket.ps1
```

生成 16 像素源坐标平移请求（序号 2）：

```powershell
.\sim\Build-UartPacket.ps1 -Sequence 2 -PoseValid $true -Words `
  00010000 00000000 00100000 `
  00000000 00010000 00000000 `
  00000000 00000000 40000000
```

将输出的 65 个字节粘贴到串口助手的 Hex 发送框。合法帧应返回头部 `A5 5A 02 81`、相同序号、状态 `00`、系数回显和 20 字节扩展区回显。再发不同平移量可观察更新；不合法 CRC 应返回状态 `04`，并保持原参数不变。

也可运行工程内的单帧串口测试脚本，默认发送一组示例旋转矩阵到 COM7 并读取完整 65 字节响应：

```powershell
.\sim\Run-UartAngleCorrection.ps1 -Com COM7
```

## 仿真和构建

请先运行 K3 映射链回归，再运行完整 PDS 流程。构建生成配套 bitstream/FIC，烧录时从本工程 `generate_bitstream/` 取文件。

```powershell
.\sim\Run-Stage8HomographyChain.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2'
.\sim\Run-UartHomographyControl.ps1
.\sim\Build-UartPacket.ps1
.\Build-UartParameterTest.ps1
```

UART 仿真直接按 8-N-1 发送完整参数帧并接收 FPGA 响应，检查 ACK/NACK、CRC、序号、系数回显，以及活动矩阵只在模拟帧边界更新。PDS 构建生成匹配的 `.sbit/.fic`；烧录后用本工程配套 FIC。用户已确认本工程位流上板运行正常；约 40 秒采样为 58.625 fps，未见丢帧，帧处理周期约 14.76 ms。

## 流水线与时序

单应映射器为 17 级弹性流水线，复位后的有效像素延迟为 17 个时钟周期；流水线灌满后仍可每周期接收一个像素，并在下游阻塞时连同坐标、像素和帧元数据一起停顿。本版本把投影系数乘加、倒数估算与修正、以及 44×33 位坐标乘法拆到多级寄存器间，避免单拍承载整段宽位运算。

Brown-Conrady `k3` 支路对 r⁶ 乘法采用分段部分积与寄存器级联，并与主 Brown 支路的像素元数据、有效信号和反压对齐。布局布线发现 r²→r⁴ 平方乘法是原关键路径；输入范围限定归一化半径后，r² 小于 12（Q16.16），因此 r² 采用有符号 21 位平方，降低 DSP 级联路径。

2026-10-28 完整 PDS 布局布线报告为 `Design Summary : All Constraints Met`；慢角 `ddrphy_sysclk` setup WNS 为 `+0.193 ns`，TNS 为 0，失败端点为 0。每次修改映射器后都应重新执行仿真和完整布局布线。

Stage 11 初步完整构建于 2026-10-29 完成：PDS 布局布线成功，时序报告为 `Design Summary : All Constraints Met`；慢角 `ddrphy_sysclk` setup WNS 为 `+0.097 ns`，TNS 为 0，失败端点为 0。加强 1–5 号曲线后再次完整构建通过，增强版 `.sbit/.fic` 已更新。裕量仍较小，曲线以外的 RTL 修改后仍需重新构建并复查时序。日志为 `stage11-image-enhancement-build.log`，报告为 `report_timing/HDMI_IN_DDR3_HDMI_OUT_top.rtr`。



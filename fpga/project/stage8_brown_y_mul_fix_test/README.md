# Stage 8 Brown Y 乘法修复测试工程

本工程独立复制自 `stage8_angle_correction_copy`，用于验证黑区对应的 Brown Y 坐标错误。它保留副本中的标定参数、1280×720 视频链路、DDR、管脚约束及 Fabric Debugger 探针。

## 故障与修改

实板在目标像素 `0x8F087` 附近观测到 `total_y8=-406`（Q16.16），但 `correction_y9=0x017AB5D6`；根据 `FY_Q16=55958233`，正确有符号结果应为 `0xFFFAB5D6`，差值恰好为 `0x01800000`，即 +384 像素。相邻像素重复出现相同偏移。RTL 仿真中的原有有符号乘法正确，故障出现在 PDS 实现后的乘法结果高位路径。

`fractional_brown_mapper.sv` 现在把 Y 位移的绝对值、无符号乘法、负号恢复分配到 S8、S9、S10 三个寄存级，并在 S11 与输入 Y 相加。负值恢复保留原有算术右移向负无穷取整语义。X 路径保持原算法，仅延迟一个周期与 Y 对齐。模块整体增加一个周期，吞吐率不变，`valid/ready`、像素 ID、帧元数据和有效标志同步延迟。

## 验证与构建

从本目录运行：

```powershell
.\sim\Run-BrownSignedCorrection.ps1
.\sim\Run-Stage8HomographyChain.ps1
.\Build-AngleCorrection.ps1
```

前两项分别验证黑区实测坐标和 Stage 8 整条坐标流水线。构建脚本检查 PDS 错误、256 个探针、时序约束，并把同次综合的 FIC 复制到 `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic`，与同目录 `.sbit` 配套。实板烧录必须使用这对文件；探针含义见 [README_JTAG.md](README_JTAG.md)。

顶层角度参数输入仍固定为零，因此工程运行恒等单应变换加标定 Brown 映射。标定中的 `k3` 尚未实现。

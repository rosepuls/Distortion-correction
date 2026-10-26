# Stage 9 Catmull–Rom + 标定 Brown 修复测试工程

本工程从当前 `stage9_bicubic_catmull_rom` 复制，独立验证已在 Stage 8 上板恢复正常画面的坐标映射与 Stage 9 插值链路。原 Stage 9 工程保留供对照。生成目录不作为复制种子；新位流与 FIC 必须在本工程重新构建。

## 坐标映射变更

旧 Stage 9 工程仍使用试验 Brown 系数、中心点 `(640,360)` 和 512 焦距。本副本把 `fractional_brown_mapper.sv` 换为 Stage 8 实板验证版：根据 `calibration.json` 的 `cx/cy/fx/fy` 归一化，使用 Q20 的 `k1/k2/p1/p2`，并将负 Y 位移取绝对值、无符号乘法、恢复符号分别放在 S8/S9/S10。X、Y、像素 ID、帧元数据和有效位随流水级同步。Brown 校正相对旧 Stage 9 增加四个寄存级，吞吐率不变。`k3` 尚未实现，动态角度包仍未接入顶层。

Stage 9 插值部分继续保留原有结构：默认 Catmull–Rom 双三次 4×4，编译期可选严格边界双线性 2×2。切换开关位于 `source/rtl/correction/stage9_interpolation_config.vh`，更换模式后须重新构建。UART 仍只接收 P14 上的 115200/8-N-1 字节，不解析命令或切换算法。

## 验证

在本工程目录运行：

```powershell
.\sim\Run-BrownSignedCorrection.ps1
.\sim\Run-Stage8HomographyChain.ps1
.\sim\Run-Stage9BicubicFrame.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2'
.\sim\Run-Stage9BicubicFrame.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2' -Bilinear
.\Build-Stage9Bicubic.ps1
```

Brown 定向测试覆盖旧板端黑区对应的负 Y 校正值；坐标链测试覆盖回压、60 组参考向量和边界。两种插值模式的 64×8 小帧测试用于防止 Stage 9 采样链路退化。完整 PDS 构建脚本检查选中的插值模块、256 个 Fabric Debugger 性能计数通道和布线后时序，并将同次综合 FIC 复制到 `generate_bitstream/`。探针定义见 [README_JTAG.md](README_JTAG.md)。

旧 Stage 9 工程的时序、位流和 FIC 均不适用于本副本。新工程是否能在实板获得预期双三次画面，需用本工程生成的 `.sbit` 与 `.fic` 实测确认。

## 本次构建结果（2026-10-26）

默认 Catmull–Rom 模式完整 PDS 构建通过，Fabric Debugger 256 通道插入成功，布线后报告 `All Constraints Met`。125 MHz `ddrphy_sysclk` setup WNS 为 **+0.016 ns**、TNS 为 0、失败端点为 0。该裕量很小，修改 RTL 或工程设置后必须重新跑完整时序。

| 生成文件 | 字节 | SHA-256 |
|---|---:|---|
| `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit` | 9,188,552 | `3C73F21353550C56C3E8357A00E355B421794A313CE17F79192CE7A4216EAA99` |
| `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic` | 22,433 | `31EA1CB5CDA0B2FB33D737C6BFB78A926433F7516EB37497A649295606209803` |

输出 FIC 与本次综合输入 FIC 的 SHA-256 一致。定向 Brown 仿真、Stage 8 坐标链与 60 组参考向量、Stage 9 双三次及双线性 64×8 帧仿真均通过。当前还没有新 Stage 9 位流的实板图像和帧率结果。

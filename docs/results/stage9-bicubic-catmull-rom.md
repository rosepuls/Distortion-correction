# Stage 9 Catmull–Rom 双三次插值结果

日期：2026-10-25
分支：`新插值算法`
器件：Pango PG2L200H-6 / FBB676
工具：PDS Fabric Compiler 2022.2-SP6.4 build 146967

## 实现

Stage 9 从 Stage 8 角度纠正工程复制出独立工程，保留单应性和 fractional Brown 坐标链，并将双线性采样替换为严格边界的 4×4 邻域采样和可反压的 Catmull–Rom (`a=-0.5`) 双三次插值。像素格式为 RGBX8888，X 字节输出为 0。坐标系数使用 Q2.14 权重；插值器包含弹性流水级。Stage 8 基线未修改。

邻域读取复用现有 tile cache，每个输出采样按顺序进行 4 次 2×2 cache lookup。只有完整 4×4 邻域均在图像范围内时才输出插值像素；边缘无效点输出黑色并保留流元数据。

## 仿真

以下项目均通过：

| 检查 | 命令 | 结果 |
|---|---|---|
| 固定点 Python 参考 | `pytest host\reference\test_bicubic_interpolator_reference.py -q` | 5 passed |
| 邻域规划器 | `.\fpga\project\stage9_bicubic_catmull_rom\sim\Run-Stage9BicubicPlanner.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2'` | PASS |
| 4×4 cache 邻域读取 | `.\fpga\project\stage9_bicubic_catmull_rom\sim\Run-Stage9BicubicReader.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2'` | PASS |
| Catmull–Rom RTL | `.\fpga\project\stage9_bicubic_catmull_rom\sim\Run-Stage9CatmullRomInterpolator.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2'` | PASS；覆盖数值、饱和、元数据及反压 |
| 集成帧仿真 | `.\fpga\project\stage9_bicubic_catmull_rom\sim\Run-Stage9BicubicFrame.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2'` | PASS；64×8 |
| Full HD 集成帧仿真 | `.\fpga\project\stage9_bicubic_catmull_rom\sim\Run-Stage9BicubicFrame.ps1 -VivadoHome 'D:\Xilinx\Vivado\2020.2' -FullHd` | PASS；1280×720，共 921,600 个输出像素 |

帧仿真使用确定性的 DDR 模型和 identity transform，不代表板上帧率。

## PDS 构建

最初不含 UART RX 的 Stage 9 构建完成了 PDS、Fabric Debugger 插入、布局布线、时序分析和 bitstream 生成。该次时序报告为 `All Constraints Met`；关键 `ddrphy_sysclk` 时钟目标 125 MHz，估计频率 125.5808 MHz，slack 为 +0.037 ns，失败 setup endpoints 为 0/61,596。这个结果只属于当时的 RTL，不能代表后续 UART 和双线性选择改动。

综合资源统计：24,640 LUT（15.42%），14,271 registers（4.47%）。这些是综合结果，不是板上功耗或实测性能数据。

该次历史构建生成的 bitstream 和 Fabric Debugger 配置哈希如下；输出目录中的位流后来已被 UART 版构建覆盖：

| 文件 | 大小 | SHA-256 |
|---|---:|---|
| `fpga/project/stage9_bicubic_catmull_rom/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit` | 9,188,552 bytes | `79B815D7225A256D9FAE2364F918B5E8D24813EA64AC9EFB79A0D834800D2CA1` |
| `fpga/project/stage9_bicubic_catmull_rom/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic` | 22,417 bytes | `D1FDB7592A3BCF4979C8B4B0A9596ACB6E865D5F23BA1F6EF994263379A90DF7` |

构建脚本确认 FIC 含 256 个通道、所有所需帧计数和性能诊断信号；导出的 `.fic` 与综合阶段使用的 FIC SHA-256 完全一致。

### Catmull–Rom 流水拆分后的完整构建（2026-10-25 12:42）

UART 版完整构建曾在 `ddrphy_sysclk` 125 MHz setup 下出现 -0.179 ns slack。时序路径检查定位到 Catmull–Rom 水平四项乘积相加后进入下一级寄存器的组合逻辑。将四项累加拆为两组部分和与最终水平和两个流水级后，Catmull–Rom RTL 仿真、64×8 整帧仿真和 1280×720 全帧仿真均通过。

新版本完整 PDS 构建、布局布线和位流导出成功。时序报告为 `All Constraints Met`；`ddrphy_sysclk` 请求 125 MHz、估计 127.081 MHz，slack **+0.131 ns**，失败 setup endpoints 为 **0/63,190**。综合资源为 24,663 LUT、14,430 registers。

| 文件 | 大小 | SHA-256 |
|---|---:|---|
| `fpga/project/stage9_bicubic_catmull_rom/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit` | 9,188,552 bytes | `6B7224CC56A6CE352BCB46CDE581CFE9F8D4298EBF71B72620CFDD520AC04040` |
| `fpga/project/stage9_bicubic_catmull_rom/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic` | 22,417 bytes | `D1FDB7592A3BCF4979C8B4B0A9596ACB6E865D5F23BA1F6EF994263379A90DF7` |

构建脚本确认本次默认模式为 Catmull–Rom 双三次、FIC 含 256 个通道，且导出的 `.fic` 与同次综合使用的 FIC 哈希一致。位流可用于本次上板测试；板上帧率仍需使用这对 `.sbit/.fic` 实测。

### UART RX 版完整构建（2026-10-25 11:24）

加入 UART RX 后重新运行了完整 PDS 流程，RTL、综合、Fabric Debugger 插入、布局布线及位流生成完成。后置时序报告为 `Some Constraints Violated`：`ddrphy_sysclk` 125 MHz setup 最差 slack **-0.179 ns**，TNS -1.032 ns，共 13 个失败端点。`Build-Stage9Bicubic.ps1` 因未满足 `All Constraints Met` 而报错；因此这次位流不属于时序通过的正式交付。

| 文件 | 大小 | SHA-256 |
|---|---:|---|
| UART 版 `.sbit` | 9,188,552 bytes | `892F3D325FCFE033BCAAE8C85467EC5C10CF71FF49238981F3DB1BCEFDFC8B59` |
| 同次综合 FIC | 22,417 bytes | `D1FDB7592A3BCF4979C8B4B0A9596ACB6E865D5F23BA1F6EF994263379A90DF7` |

FIC 与同次综合的 256 通道 FIC 哈希一致。随后加入的编译期双线性选择尚未通过完整 PDS 构建；上表 UART 位流不包含本次双线性代码。默认双三次和双线性两种 64×8 帧仿真、双线性半像素与反压单元仿真均已通过。

### 编译期双线性选择检查

`stage9_interpolation_config.vh` 默认不定义 `STAGE9_USE_BILINEAR`。Vivado 仿真器与 PDS 均确认默认配置展开双三次规划器、4×4 读取器和 Catmull–Rom 插值器；定义宏后展开双线性规划器、2×2 cache 读取器和双线性插值器。两次 PDS `synthesize` 都通过，综合统计如下：

| 配置 | LUT | 寄存器 | 验证 |
|---|---:|---:|---|
| 默认双三次 | 24,758 | 14,310 | 与选择功能加入前的 UART 版综合统计完全相同 |
| 双线性 | 23,558 | 12,073 | PDS 综合成功；64×8 帧仿真和半像素/反压单元仿真通过 |

这些统计只证明综合阶段没有同时保留两套采样链；双线性选择目前有综合和仿真验证，未进行完整布局布线。完成双线性综合检查后，配置头文件已恢复默认双三次。

## 板上帧率

尚未获得用户对新位流的板上测量。进行板上测量时，必须使用同一次构建的 Stage 9 `.sbit/.fic`，并依据 `README_JTAG.md` 中的帧周期计数器测量。Stage 8 的 FIC 不适用于读取 Stage 9 计数器。

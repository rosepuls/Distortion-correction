# Stage 9 编译期双线性插值实施计划

> **For agentic workers:** Inline execution in this session; each checkbox is a reviewable implementation step.

**Goal:** 在 Stage 9 中通过综合前宏选择双线性或 Catmull–Rom 双三次，默认仍为双三次。

**Architecture:** 在 `stage5_identity_pipeline.sv` 的坐标链之后按预处理宏只保留一种规划器、cache 读取器和插值器。两种模式连接同一对外读写与元数据接口。

**Tech Stack:** SystemVerilog、Pango PDS 2022.2-SP6.4、Vivado Simulator 2020.2、PowerShell。

## Global Constraints

- 只修改 Stage 9 工程及相关文档；Stage 8 不变。
- 默认 Catmull–Rom 双三次；定义 `STAGE9_USE_BILINEAR` 才构建双线性。
- 双线性沿用现有 2×2 模块并启用严格黑边；保持 RGBX8888 与标准流元数据。
- 每次完整位流构建需使用同次综合的 Fabric Debugger FIC；报告真实时序结果。

---

### Task 1: 配置和数据通路

**Files:**
- Create: `fpga/project/stage9_bicubic_catmull_rom/source/rtl/correction/stage9_interpolation_config.vh`
- Modify: `fpga/project/stage9_bicubic_catmull_rom/source/rtl/correction/stage5_identity_pipeline.sv`
- Modify: `fpga/project/stage9_bicubic_catmull_rom/HDMI_IN_DDR3_HDMI_OUT.pds`

**Interfaces:** 双线性分支接受坐标链的 `sx/sy`、标准元数据以及现有 DDR cache 接口；输出与双三次分支同名、同宽的顶层流信号。

- [x] 在配置头文件中保留默认双三次的未定义宏状态，并写明如何启用 `STAGE9_USE_BILINEAR`。
- [x] 在现有双三次链前后放置条件预处理分支，新增双线性规划器 `STRICT_BLACK_BORDER=1`、2×2 cache reader、流水插值器，逐项连接 `valid/ready`、DDR 请求、诊断及元数据。
- [x] 将三份已存在的双线性 RTL 加入 PDS 源文件列表；确认 UART 文件仍在列表内。

### Task 2: 两种模式的集成检查

**Files:**
- Modify: `fpga/project/stage9_bicubic_catmull_rom/sim/Run-Stage9BicubicFrame.ps1`
- Create or modify: Stage 9 frame integration testbench/runner as needed for mode selection.

**Interfaces:** 仿真通过项目根目录 include path 读取配置头；双线性构建允许命令行定义相同的模式宏。

- [x] 保持默认双三次 64×8 帧仿真通过，并验证输出顺序及严格 4×4 黑边。
- [x] 增加双线性半像素数值/反压单元仿真，并在 64×8 帧仿真中检查 2×2 黑边、像素与帧元数据、缓存和 DDR 读取完整结束。
- [x] 对更改文件执行 `git diff --check`，并检查 Stage 8 不在提交内容中。
- [x] 用 PDS 分别综合两种模式，确认实例选择；恢复默认双三次后重新综合。

### Task 3: 文档和 Git 提交

**Files:**
- Modify: `fpga/project/stage9_bicubic_catmull_rom/README.md`
- Create/update: `docs/chat/Add-new-algorithm.md`
- Modify: `docs/results/stage9-bicubic-catmull-rom.md`

- [x] 文档说明综合前切换方法、默认模式、两种边界和同次构建 FIC 要求；将最近 UART 位流的 `-0.179 ns` 时序违例与先前通过的构建分开记录。
- [x] 只暂存本次 Stage 9 与既有未提交的相关成果，检查暂存文件及大小后提交到 `新插值算法` 分支。

## 验证记录

- `Run-Stage9BicubicFrame.ps1`：64×8 默认双三次，PASS。
- `Run-Stage9BicubicFrame.ps1 -Bilinear`：64×8 双线性，PASS。
- `Run-Stage9BilinearInterpolator.ps1`：半像素插值、反压、元数据，PASS。
- PDS `-run synthesize`：默认双三次 24,758 LUT/14,310 寄存器；双线性 23,558 LUT/12,073 寄存器；恢复默认后再次综合，三次均成功。
- 未对新选择功能运行完整布局布线或重新生成位流；前次 UART 版构建的时序违例见 `docs/results/stage9-bicubic-catmull-rom.md`。

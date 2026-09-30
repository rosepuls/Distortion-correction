# 基于紫光同创盘古50 MES50HP（PGL50H）的视频畸变矫正与轻量视觉处理系统项目计划

## 1. 项目定位

本项目基于 **紫光同创盘古50 MES50HP 开发板（FPGA：PGL50H-6IFBG484）**，使用 **PDS 2022.2** 作为主要 FPGA 开发环境，构建一套面向实时视频的轻量视觉处理系统。该板卡属于《全国大学生嵌入式芯片与系统设计竞赛 2026 选题指南（紫光同创）》列出的推荐平台，板载由两颗 x16 器件组成的 32 bit DDR3 存储通道，并提供 HDMI 收发接口，适合完成本项目的视频采集、缓存、畸变矫正与显示链路。

PDS 版本不在算法源码中写死。首次建板级工程时优先验证当前官方稳定版本 `PDS 2022.2-SP6.7.1`；若 MES50HP 官方例程、DDR3 IP 或赛事资料明确依赖旧版本，则使用与例程和 IP 匹配的 PDS 2022.2 版本。

项目不采用 YOLO 等深度学习目标检测网络，而是围绕 FPGA 更擅长的流式图像处理方式，完成：

- HDMI 视频输入与输出；
- DDR3 帧缓存；
- 灰度化、亮度调整、Gamma 等基础图像增强；
- 3×3 高斯滤波；
- Sobel 边缘检测；
- 阈值二值化；
- 形态学处理；
- 连通域分析与目标区域提取；
- 二阶径向畸变矫正；
- 切向畸变矫正；
- 双线性插值；
- 畸变标靶/ROI 自动检测；
- 矫正前后效果评价；
- 后续资源、带宽、时序优化。

无板卡建模和首次上板阶段以：

```text
1280 × 720 @ 60 fps
```

作为开发里程碑。

根据 2026 竞赛指南，最终验收目标至少为：

```text
1920 × 1080 @ 30 fps
```

资源和时序允许时进一步挑战：

```text
1920 × 1080 @ 60 fps
```

## 1.1 盘古50 MES50HP 板卡适配说明

本项目后续统一以以下硬件平台为目标：

```text
开发板：盘古50 MES50HP
FPGA：PGL50H-6IFBG484
存储：2 × 512 MB DDR3（每颗 x16，共同组成单个 x32 接口）
DDR3：最高 400 MHz / 800 MT/s，理论峰值 25.6 Gbit/s（3.2 GB/s）
视频输入：MS7200 HDMI Receiver，24 bit 并行视频口
视频输出：MS7210 HDMI Transmitter，24 bit 并行视频口
板载时钟：50 MHz、27 MHz、125 MHz HSST 差分参考时钟
开发工具：PDS 2022.2；优先验证 SP6.7.1，例程/IP 要求时使用匹配版本
```

代码从一开始分成两层：

```text
算法层（尽量与板卡无关）
├── RGB2Gray
├── Gaussian
├── Brightness / Gamma
├── Sobel / Threshold / Morphology
├── Connected Component
├── Distortion Core
└── Bilinear Interpolation

板卡层（MES50HP 专用）
├── Clock / PLL
├── Reset
├── I²C Master
├── MS7200 Init / HDMI RX Interface
├── MS7210 Init / HDMI TX Interface
├── Video CDC / Async FIFO
├── DDR3 Controller / Frame Buffer
├── Pin Constraints
└── top.sv
```

这样当前使用 Vivado 做纯 RTL 仿真时写出的算法模块，后续迁移到 PDS / PGL50H 时基本无需重写；真正需要重新适配的是时钟、DDR、HDMI、引脚约束以及顶层连接。

MES50HP 的两颗 x16 DDR3 共同组成一个 x32 存储通道，不按两个独立通道规划。第一版优先按照官方 MES50HP 示例工程和匹配版本的 DDR3 IP 打通稳定的 Frame Buffer；随后再根据 1080P、高并发 Pixel Fetch 和缓存优化需求，提高突发效率与有效带宽。

## 1.2 PGL50H 资源预算基线

根据 MES50HP 硬件手册，PGL50H-6IFBG484 的主要资源为：

| 资源 | 数量 | 项目用途 |
|---|---:|---|
| FF | 64,200 | 流水寄存器、状态机、缓存控制 |
| LUT6 | 42,800 | 定点加法、控制逻辑、地址生成 |
| 18 Kbit DRM | 134 | 行缓存、FIFO、Local Pixel Cache |
| APM 乘法单元 | 84 | 畸变坐标、增益和双线性插值 |
| HSST | 4 路 | 本项目基础视频链暂不依赖 |

初期只把这些数据作为资源预算上限，不使用 Vivado 综合结果代替 PDS 的最终资源报告。建议至少为板卡接口、CDC、DDR3 控制和后续调试预留约 15% 的 LUT/FF 余量；APM 与 DRM 的具体配额在定点模型和 PDS 综合后再冻结。

## 1.3 时钟域与 CDC 基线

完整系统至少包含以下时钟域：

```text
50 MHz System / I²C Configuration Domain
HDMI RX Pixel Clock Domain（来自 MS7200）
DDR3 User Clock Domain（来自 DDR3 IP）
Image Processing Clock Domain
HDMI TX Pixel Clock Domain（送往 MS7210）
```

必须明确：

- 单 bit 控制信号采用双触发器同步或握手同步；
- 像素流跨域采用异步 FIFO 或帧缓存；
- `pixel/valid/sof/eol` 作为一个整体跨域，不能分别同步；
- 每个时钟域独立完成复位同步释放；
- HDMI RX PCLK、DDR3 用户时钟和 HDMI TX PCLK 不假设同频同相；
- Testbench 和上板验证都要覆盖 CDC 缓冲区接近满/空的情况。

---

# 2. 项目总体目标

最终系统希望形成以下完整链路：

```text
PC / Camera
    │
    ▼
 HDMI RX
    │
    ▼
颜色格式处理
RGB / Gray
    │
    ▼
基础图像预处理
├─ 3×3 Gaussian
├─ Brightness / Gain
└─ Gamma LUT
    │
    ▼
DDR3 Frame Buffer
    │
    ├───────────────────────────────┐
    │                               │
    ▼                               ▼
目标 / 标靶检测支路               畸变矫正支路
Sobel                           Coordinate Generator
  │                                  │
Threshold                            Distortion Model
  │                                  │
Morphology                           Source Coordinate
  │                                  │
Connected Component                  Pixel Fetch
  │                                  │
ROI / Bounding Box                   Bilinear Interp
    │                               │
    └──────────────┬────────────────┘
                   │
                   ▼
             结果融合 / 标注
                   │
                   ▼
              HDMI TX
                   │
                   ▼
                Monitor
```

项目重点不是堆大量算法，而是做一套：

> **可实时、可验证、可优化、具有一定视觉分析能力的 FPGA 图像处理系统。**

---

# 3. 项目功能分层

整个系统建议划分为三层。

## 3.1 第一层：基础图像预处理

主要包括：

```text
RGB → Gray
3×3 Gaussian
Brightness / Gain
Gamma LUT
```

目的：

- 去除简单噪声；
- 改善亮度；
- 提高后续目标/边缘检测稳定性；
- 为真实摄像头输入做准备。

---

## 3.2 第二层：核心几何矫正

包括：

```text
径向畸变
+
切向畸变
+
反向坐标映射
+
双线性插值
```

这是整个项目的核心算法部分。

---

## 3.3 第三层：轻量视觉分析

包括：

```text
Sobel
↓
Threshold
↓
Morphology
↓
Connected Component
↓
ROI / Bounding Box
↓
畸变标靶识别 / 目标区域识别
```

不使用 YOLO。

主要目的是：

- 找到测试标靶；
- 找到明显目标区域；
- 提取 Bounding Box；
- 自动统计矫正前后的边缘、直线、ROI 信息；
- 为后续自适应处理提供依据。

---

# 4. 阶段 0：开发环境与板卡基础验证

开发环境：

```text
Windows
  │
  └── PDS 2022.2
          ├── 优先验证 SP6.7.1
          └── 官方例程 / IP 指定版本时使用匹配版本
          │
          └── 盘古50 MES50HP / PGL50H-6IFBG484
```

## 主要任务

1. 新建工程；
2. Verilog / SystemVerilog 基础编译；
3. 综合；
4. 布局布线；
5. 生成配置文件；
6. JTAG 下载；
7. LED 点灯；
8. PLL 测试；
9. 时钟与复位模块验证。

## 阶段目标

打通：

```text
RTL
↓
Synthesis
↓
Place & Route
↓
Bitstream
↓
JTAG
↓
Board
```

---

# 5. 阶段 1：HDMI 视频链路

## 5.1 HDMI 输出

首先让 FPGA 自己生成：

```text
Color Bar
Gray Ramp
Grid
Checkerboard
```

第一版分辨率：

```text
1280 × 720 @ 60 Hz
```

验证：

- 分辨率正确；
- 时序稳定；
- 无花屏；
- 无闪烁；
- 显示器识别正常。

---

## 5.2 HDMI 输入直通

实现：

```text
PC HDMI
   ↓
HDMI RX
   ↓
Pixel Stream
   ↓
HDMI TX
   ↓
Monitor
```

暂时：

```text
RGB_out = RGB_in
```

完成 HDMI Pass-Through。

---

# 6. 阶段 2：基础图像预处理

这一阶段先不接畸变矫正。

目标是建立独立、可开关的流式图像预处理链。

建议模块：

```text
rgb2gray.sv
gaussian_3x3.sv
brightness_gain.sv
gamma_lut.sv
```

---

# 7. RGB 转灰度

建议使用定点近似：

\[
Gray = 0.299R + 0.587G + 0.114B
\]

FPGA 中可采用整数形式，例如：

\[
Gray \approx \frac{77R + 150G + 29B}{256}
\]

这样可以通过：

```text
乘法
+
加法
+
右移 8 bit
```

实现。

灰度图主要提供给：

- Sobel；
- Threshold；
- Morphology；
- Connected Component。

原 RGB 数据仍可保留给最终显示。

---

# 8. 3×3 高斯滤波

第一版建议使用：

\[
\frac{1}{16}
\begin{bmatrix}
1 & 2 & 1 \\
2 & 4 & 2 \\
1 & 2 & 1
\end{bmatrix}
\]

优势：

- 系数简单；
- 可用移位加法实现；
- 不需要复杂乘法；
- 适合 FPGA 流水线。

计算：

\[
P_{out}=
\frac{
P_{00}+2P_{01}+P_{02}
+2P_{10}+4P_{11}+2P_{12}
+P_{20}+2P_{21}+P_{22}
}{16}
\]

最后：

```text
>> 4
```

即可完成除 16。

---

## 8.1 行缓存结构

3×3 滤波需要三行像素：

```text
Line Buffer 0
Line Buffer 1
Current Line
```

结构：

```text
Pixel Stream
    │
    ▼
Line Buffer
    │
    ▼
3 × 3 Window Generator
    │
    ▼
Gaussian
```

这个窗口结构以后还能复用给：

- Sobel；
- Morphology；
- Sharpen。

---

# 9. 亮度与对比度调整

采用：

\[
Y_{out} = \alpha Y_{in} + \beta
\]

其中：

- \(\alpha\)：对比度/Gain；
- \(\beta\)：亮度 Offset。

FPGA：

```text
Pixel
  ↓
Multiply Gain
  ↓
Add Offset
  ↓
Saturation
  ↓
0 ~ 255
```

需要进行饱和处理：

```text
< 0   → 0
> 255 → 255
否则  → 原值
```

这个模块资源消耗低，建议作为可配置模块保留。

---

# 10. Gamma 校正

Gamma 不采用实时指数运算。

直接建立：

```text
256 × 8 bit LUT
```

输入像素：

```text
0 ~ 255
```

作为 ROM 地址。

输出：

```text
Gamma(pixel)
```

结构：

```text
8-bit Pixel
    ↓
 Gamma LUT
    ↓
8-bit Pixel
```

优点：

- 资源低；
- 延迟固定；
- 易动态切换不同 Gamma 表。

---

# 11. 阶段 3：DDR3 Frame Buffer

盘古50 MES50HP 板载两颗 x16 DDR3，两颗器件共同构成一个 x32 DDR3 存储通道，总容量 1 GB。畸变矫正必须支持非顺序访问，因此需要完整帧缓存。第一版先以“稳定完成帧写入、帧读取和 Ping-Pong”为目标，不急于做复杂的多主机并发访问；DDR 控制部分优先参考 MES50HP 官方示例和匹配版本的 PDS DDR3 IP。

基础结构：

```text
HDMI RX
   │
   ▼
Write FIFO
   │
   ▼
DDR3
   │
   ▼
Read FIFO
   │
   ▼
Processing
   │
   ▼
HDMI TX
```

---

## 11.1 Ping-Pong Buffer

采用：

```text
Frame A：写
Frame B：读

下一帧：

Frame B：写
Frame A：读
```

目的：

- 避免同一帧读写冲突；
- 降低撕裂；
- 为畸变随机访问提供基础。

---

# 12. 阶段 4：PC 端算法 Golden Model

软件目录建议：

```text
software/
├── calibration.py
├── preprocess_model.py
├── golden_model.py
├── fixed_point_model.py
├── target_detect_model.py
└── compare.py
```

使用：

```text
Python
NumPy
OpenCV
```

但 FPGA 对应算法应尽量自己实现。

OpenCV 主要作为参考。

竞赛最终测试必须使用真实相机标定结果，不能只使用人为构造的 `fx/fy/cx/cy/k1/k2/p1/p2`。无板阶段允许使用人工参数验证数据通路；相机、镜头和采集链确定后，必须使用棋盘格或圆点阵列重新标定，并保存：

```text
原始标定图像
相机内参矩阵
畸变系数
重投影误差
标定脚本与软件版本
最终加载到 FPGA 的定点参数
```

---

# 13. 畸变模型

相机内参：

\[
K=
\begin{bmatrix}
f_x & 0 & c_x\\
0 & f_y & c_y\\
0 & 0 & 1
\end{bmatrix}
\]

畸变参数：

\[
k_1,k_2,p_1,p_2
\]

---

## 13.1 输出坐标归一化

\[
x=\frac{u-c_x}{f_x}
\]

\[
y=\frac{v-c_y}{f_y}
\]

计算：

\[
r^2=x^2+y^2
\]

\[
r^4=r^2r^2
\]

径向畸变：

\[
L=1+k_1r^2+k_2r^4
\]

切向畸变：

\[
x_d=xL+2p_1xy+p_2(r^2+2x^2)
\]

\[
y_d=yL+p_1(r^2+2y^2)+2p_2xy
\]

重新映射：

\[
u_s=f_xx_d+c_x
\]

\[
v_s=f_yy_d+c_y
\]

采用：

> **反向映射**

即：

```text
Output Coordinate
      ↓
Source Coordinate
```

避免正向映射产生空洞。

---

# 14. 双线性插值

对于：

\[
u_s = x_0 + d_x
\]

\[
v_s = y_0 + d_y
\]

获取：

```text
P00 = I[y0][x0]
P10 = I[y0][x0+1]
P01 = I[y0+1][x0]
P11 = I[y0+1][x0+1]
```

采用两级插值：

\[
P_t=P_{00}+(P_{10}-P_{00})d_x
\]

\[
P_b=P_{01}+(P_{11}-P_{01})d_x
\]

\[
P=P_t+(P_b-P_t)d_y
\]

相比四权重直接相乘，更适合 FPGA 流水线。

---

# 15. 阶段 5：畸变算法定点化

第一版可以从以下位宽开始研究：

| 数据 | 初始格式建议 |
|---|---|
| x / y | signed Q4.28 |
| k1 / k2 | signed Q4.28 |
| p1 / p2 | signed Q4.28 |
| r² / r⁴ | 扩位 |
| us / vs | Q13.19 |
| dx / dy | Q0.16 |
| RGB | 8 bit |

最终不要统一使用一种位宽。

需要分别分析：

```text
x/y
k1/k2
p1/p2
r²
r⁴
us/vs
dx/dy
```

比较：

- 最大坐标误差；
- 平均坐标误差；
- MAE；
- MSE；
- PSNR；
- LUT；
- APM；
- Fmax。

---

# 16. 阶段 6：Distortion RTL

建议模块：

```text
coordinate_gen.sv
normalize.sv
distortion_core.sv
coordinate_split.sv
```

流水线：

```text
Stage 0
u,v
 │
 ▼
Stage 1
u-cx, v-cy
 │
 ▼
Stage 2
x,y
 │
 ▼
Stage 3
x²,y²,xy
 │
 ▼
Stage 4
r²
 │
 ▼
Stage 5
r⁴
 │
 ▼
Stage 6
Radial
 │
 ▼
Stage 7
Tangential
 │
 ▼
Stage 8
xd,yd
 │
 ▼
Stage 9
us,vs
```

目标：

```text
1 Pixel / Clock
```

---

# 17. 阶段 7：轻量目标与标靶检测

这一部分不使用 YOLO。

目标是通过传统 FPGA 图像算法完成：

```text
Gray
 ↓
Gaussian
 ↓
Sobel
 ↓
Threshold
 ↓
Morphology
 ↓
Connected Component
 ↓
Bounding Box
```

可以用于：

- 检测测试标靶；
- 检测明显工件/矩形目标；
- 检测网格区域；
- 获取 ROI；
- 显示目标边框；
- 统计矫正前后边缘变化。

---

# 18. Sobel 边缘检测

使用经典核：

\[
G_x=
\begin{bmatrix}
-1&0&1\\
-2&0&2\\
-1&0&1
\end{bmatrix}
\]

\[
G_y=
\begin{bmatrix}
-1&-2&-1\\
0&0&0\\
1&2&1
\end{bmatrix}
\]

边缘幅值第一版建议近似：

\[
G \approx |G_x|+|G_y|
\]

而不是：

\[
\sqrt{G_x^2+G_y^2}
\]

避免平方根运算。

---

# 19. 二值化

简单阈值：

\[
B(x,y)=
\begin{cases}
1,& G(x,y)>T\\
0,& G(x,y)\le T
\end{cases}
\]

阈值 \(T\) 通过寄存器配置。

后续可以做：

- 固定阈值；
- 简单自适应阈值；
- 不同场景切换阈值。

---

# 20. 形态学处理

建议先实现：

```text
3×3 Erosion
3×3 Dilation
```

可以组合成：

```text
Opening
Closing
```

用途：

- 去除孤立噪点；
- 填补目标边缘小孔洞；
- 提高连通域稳定性。

---

# 21. Connected Component Labeling

不采用复杂 AI。

通过二值图进行连通域分析：

```text
Binary Image
    ↓
Run / Label
    ↓
Area
Bounding Box
Centroid
    ↓
Target Selection
```

需要统计：

```text
xmin
xmax
ymin
ymax
area
centroid_x
centroid_y
```

---

## 21.1 目标筛选

可以利用：

```text
Area
Aspect Ratio
Width
Height
Position
```

筛选目标。

例如标准测试标靶：

```text
面积范围固定
宽高比接近固定值
位置位于画面中心附近
```

这样可以非常轻量地识别目标区域。

---

# 22. 标靶检测建议

本项目比较推荐使用：

```text
Checkerboard
Grid
Rectangle Target
Dot Pattern
```

作为测试标靶。

相比识别人、汽车等自然目标，标靶：

- 更容易验证；
- 更适合 FPGA；
- 和畸变矫正高度相关；
- 可做量化评价。

---

# 23. 矫正效果自动评价

这个可以作为项目亮点。

基本思路：

```text
原始图像
   ↓
边缘检测
   ↓
提取标靶边缘
   ↓
统计弯曲 / 位置误差


矫正图像
   ↓
边缘检测
   ↓
再次提取
   ↓
统计残余误差
```

最终显示：

```text
Before Correction
Max Edge Error = XX px

After Correction
Max Edge Error = XX px
```

或：

```text
Average Edge Error
Straightness Error
ROI Position Error
MTF50
SFR
```

其中直线度误差用于评价几何矫正效果；MTF50/SFR 用于检查插值与矫正是否造成明显清晰度下降。MTF50/SFR 第一版在上位机离线计算，不强制全部在 FPGA 内实时实现。

---

# 24. 注意：目标检测与畸变矫正的关系

畸变是整个相机视场的几何问题。

因此原则上：

> 整幅图像应该进行畸变矫正。

ROI 不建议简单用于：

```text
ROI 内矫正
ROI 外不矫正
```

更合理的用途是：

- 自动找到标靶；
- 只评价 ROI 区域；
- ROI 内采用更高质量处理；
- ROI 外采用普通处理；
- 自动显示检测框；
- 自动统计畸变误差。

---

# 25. 阶段 8：双线性插值 RTL

建立：

```text
bilinear_interp.sv
```

输入：

```text
P00
P10
P01
P11
dx
dy
```

输出：

```text
RGB_out
```

RGB 可并行：

```text
R Bilinear ──┐
G Bilinear ──┼── RGB888
B Bilinear ──┘
```

---

# 26. 阶段 9：DDR Pixel Fetch

最大难点之一：

```text
src_x = 487.37
src_y = 291.82
```

需要：

```text
487,291
488,291
487,292
488,292
```

不能简单每个输出像素随机访问 DDR 四次。

需要设计：

```text
Address Generator
        ↓
Pixel Fetch
        ↓
Local Buffer / Cache
        ↓
P00 P10 P01 P11
```

---

# 27. 创新方向一：Local Pixel Cache

结构：

```text
DDR3
 │
 │ Burst
 ▼
Local DRM / Tile Cache
 │
 ├─ P00
 ├─ P10
 ├─ P01
 └─ P11
 │
 ▼
Bilinear
```

研究：

```text
Cache Hit Rate
DDR Access Count
Effective Bandwidth
FPS
```

---

# 28. 创新方向二：增量坐标生成

普通方式：

\[
x=\frac{u-c_x}{f_x}
\]

由于：

\[
u_{n+1}=u_n+1
\]

所以：

\[
x_{n+1}=x_n+\frac{1}{f_x}
\]

令：

\[
\Delta x=\frac{1}{f_x}
\]

则：

```text
x0
↓ +Δx
x1
↓ +Δx
x2
↓ +Δx
x3
```

减少重复运算。

---

## 28.1 二次项递推

\[
x_{n+1}^2
=
x_n^2+2x_n\Delta x+\Delta x^2
\]

可进一步研究：

- APM 乘法单元节省；
- LUT 增加；
- 定点累积误差；
- 多少像素重新校准一次。

---

# 29. 创新方向三：统一 3×3 窗口复用

Gaussian、Sobel、Morphology 都依赖 3×3 邻域。

可以研究：

> **共享 Line Buffer / Window Generator**

例如：

```text
Pixel
  ↓
Shared Line Buffer
  ↓
3×3 Window
  ├── Gaussian
  ├── Sobel
  └── Morphology
```

避免每个算法分别建立完整行缓存。

这个优化非常符合 FPGA 工程特点。

---

# 30. 创新方向四：可配置处理链

通过寄存器控制：

```text
Gaussian Enable
Brightness Enable
Gamma Enable
Sobel Enable
Morphology Enable
Distortion Enable
ROI Overlay Enable
```

例如：

```text
Mode 0：HDMI Direct
Mode 1：Preprocess
Mode 2：Distortion
Mode 3：Target Detect
Mode 4：Full Pipeline
```

比赛演示效果会很好。

---

# 31. 创新方向五：矫正效果在线评价

普通项目一般只显示矫正后图像。

本项目增加：

```text
标靶检测
+
边缘误差统计
+
矫正前后对比
```

从：

> 主观“看起来变直了”

升级到：

> 客观数值评价。

这是很适合比赛答辩的创新点。

---

# 32. 推荐 RTL 工程结构

```text
Distortion-correction/
│
├── rtl/
│   │
│   ├── board/
│   │   └── mes50hp/
│   │       ├── mes50hp_top.sv
│   │       ├── clock_reset.sv
│   │       ├── i2c_master.sv
│   │       ├── ms7200_init.sv
│   │       ├── ms7200_rx_if.sv
│   │       ├── ms7210_init.sv
│   │       ├── ms7210_tx_if.sv
│   │       ├── video_cdc.sv
│   │       └── ddr3_frame_buffer.sv
│   │
│   ├── video/
│   │   ├── video_timing.sv
│   │   └── video_stream_adapter.sv
│   │
│   ├── preprocess/
│   │   ├── rgb2gray.sv
│   │   ├── line_buffer_3x3.sv
│   │   ├── gaussian_3x3.sv
│   │   ├── brightness_gain.sv
│   │   └── gamma_lut.sv
│   │
│   ├── detect/
│   │   ├── sobel_3x3.sv
│   │   ├── threshold.sv
│   │   ├── morphology.sv
│   │   ├── connected_component.sv
│   │   └── bbox_overlay.sv
│   │
│   ├── memory/
│   │   ├── frame_buffer.sv
│   │   ├── ddr_write.sv
│   │   ├── ddr_read.sv
│   │   ├── pixel_fetch.sv
│   │   └── pixel_cache.sv
│   │
│   ├── distortion/
│   │   ├── coordinate_gen.sv
│   │   ├── normalize.sv
│   │   ├── distortion_core.sv
│   │   └── coordinate_split.sv
│   │
│   └── interpolation/
│       └── bilinear_interp.sv
│
├── sim/
│   ├── tb_gaussian.sv
│   ├── tb_sobel.sv
│   ├── tb_morphology.sv
│   ├── tb_ccl.sv
│   ├── tb_distortion_core.sv
│   └── tb_bilinear_interp.sv
│
├── software/
│   ├── calibration.py
│   ├── preprocess_model.py
│   ├── target_detect_model.py
│   ├── golden_model.py
│   ├── fixed_point_model.py
│   └── compare.py
│
├── constraints/
│   └── mes50hp/
│       ├── mes50hp_pgl50h.sdc
│       └── mes50hp_pgl50h.pdc
│
├── ip/
│   └── pango/
│       ├── pll/
│       └── ddr3/
│
└── docs/
    ├── board/
    └── plans/
```

---

# 33. 开发顺序建议

## 第一阶段：不需要板子也能做

现在即可推进：

```text
Python Golden Model
↓
Preprocess Model
↓
Target Detection Model
↓
Fixed Point Model
↓
Distortion RTL
↓
Gaussian RTL
↓
Sobel RTL
↓
Bilinear RTL
↓
Testbench
```

---

## 第二阶段：板子和 PDS 到位以后

```text
PDS
↓
LED
↓
PLL
↓
720P Color Bar
↓
HDMI Pass-Through
↓
DDR Frame Buffer
```

---

## 第三阶段：基础图像处理上板

```text
HDMI
↓
RGB2Gray
↓
Gaussian
↓
Brightness
↓
Gamma
↓
HDMI
```

---

## 第四阶段：畸变矫正上板

```text
HDMI
↓
DDR
↓
Distortion
↓
Pixel Fetch
↓
Bilinear
↓
HDMI
```

---

## 第五阶段：目标与标靶检测

```text
Gray
↓
Gaussian
↓
Sobel
↓
Threshold
↓
Morphology
↓
Connected Component
↓
Bounding Box
```

---

## 第六阶段：完整融合

```text
Preprocess
+
Distortion
+
Target Detection
+
Result Overlay
```

---

# 34. 建议开发周期

| 周期 | 任务 | 主要成果 |
|---|---|---|
| 第1周 | PDS / FPGA基础 | LED、PLL |
| 第2周 | HDMI | 720P 彩条、直通 |
| 第3周 | 图像预处理 | Gray、Gaussian、Brightness、Gamma |
| 第4周 | DDR3 | HDMI → DDR → HDMI |
| 第5周 | Python畸变模型 | Float Golden Model |
| 第6周 | 定点化 | Fixed vs Float |
| 第7周 | Distortion RTL | 坐标映射通过 |
| 第8周 | Bilinear + Pixel Fetch | 插值通过 |
| 第9周 | 完整畸变系统 | 720P60 实时矫正开发里程碑 |
| 第10周 | Sobel + Threshold | 边缘检测 |
| 第11周 | Morphology + CCL | ROI / Bounding Box |
| 第12周 | 系统融合 | 检测 + 矫正 |
| 第13周 | 坐标递推 | 算术资源优化 |
| 第14周 | Pixel Cache | DDR带宽优化 |
| 第15周 | 共享窗口优化 | DRM/行缓存资源优化 |
| 第16周 | 性能测试 | FPS、PSNR、Fmax、资源 |

---

# 35. 基础任务完成标准

## 视频链路

- [ ] HDMI IN 正常；
- [ ] HDMI OUT 正常；
- [ ] DDR Frame Buffer 正常；
- [ ] 720P60 稳定，作为开发里程碑；
- [ ] 1080P30 稳定，作为最终基础验收目标；
- [ ] 条件允许时验证 1080P60。

## 图像预处理

- [ ] RGB2Gray；
- [ ] Gaussian 3×3；
- [ ] Brightness / Gain；
- [ ] Gamma LUT。

## 畸变矫正

- [ ] 二阶径向畸变；
- [ ] 切向畸变；
- [ ] 反向映射；
- [ ] 双线性插值；
- [ ] Float / Fixed / RTL 对比通过。

## 目标检测

- [ ] Sobel；
- [ ] Threshold；
- [ ] Morphology；
- [ ] Connected Component；
- [ ] Bounding Box。

## 性能测试

- [ ] LUT；
- [ ] FF；
- [ ] DRM / RAM；
- [ ] APM；
- [ ] Fmax；
- [ ] FPS；
- [ ] PSNR；
- [ ] 坐标误差；
- [ ] 直线度误差；
- [ ] MTF50 / SFR；
- [ ] 端到端硬件延迟。

---

# 36. 推荐最终演示模式

建议做 5 个模式切换。

## Mode 0：原始视频

```text
HDMI → HDMI
```

## Mode 1：预处理

```text
Gaussian
+
Brightness
+
Gamma
```

## Mode 2：畸变矫正

```text
Distortion
+
Bilinear
```

## Mode 3：目标检测

```text
Sobel
+
Threshold
+
Morphology
+
Connected Component
+
BBox
```

## Mode 4：完整系统

```text
Preprocess
+
Distortion
+
Detection
+
Result Overlay
```

---

# 37. 最终可以形成的项目亮点

建议最终重点强调以下几项：

### 亮点 1：实时全定点畸变矫正

```text
Float Model
↓
Fixed Point
↓
RTL Pipeline
↓
1 Pixel / Clock
```

### 亮点 2：增量坐标计算

利用相邻像素连续性减少重复计算。

### 亮点 3：Local Pixel Cache

利用 DRM 减少 DDR 随机访问。

### 亮点 4：共享 3×3 Window Generator

Gaussian、Sobel、Morphology 共用窗口缓存架构。

### 亮点 5：轻量目标/标靶识别

不使用 YOLO，使用传统图像算法完成：

```text
Sobel
Threshold
Morphology
CCL
BBox
```

### 亮点 6：矫正效果在线评价

从主观显示升级为：

```text
Before Error
VS
After Error
```

---

# 38. 当前阶段建议优先推进

你现在虽然最终目标板已经改为 **盘古50 MES50HP / PGL50H-6IFBG484**，但在没有板子和 PDS 环境时，当前策略不变：使用 VSCode 编写 Python 与纯 RTL，使用 Vivado 只做行为级仿真，不调用 Xilinx 专用 IP。等 MES50HP 和 PDS 可用后，再做板级适配。

优先做：

```text
1. preprocess_model.py
2. golden_model.py
3. target_detect_model.py
4. fixed_point_model.py
5. gaussian_3x3.sv
6. sobel_3x3.sv
7. distortion_core.sv
8. bilinear_interp.sv
9. Testbench
```

暂时不要做：

```text
HDMI 引脚
DDR 引脚
PLL IP
JTAG
板级约束
PDS 时序收敛
```

等板子和 PDS 到位后再处理。

---

# 39. Vivado → PDS / MES50HP 迁移原则

当前阶段使用 Vivado 的目的只是验证算法 RTL，不代表最终工程使用 Xilinx FPGA。

迁移时按以下原则处理：

```text
可以直接迁移
├── 纯 Verilog / SystemVerilog 算法模块
├── Testbench 测试向量
├── Python Golden Model
├── 定点位宽方案
└── 模块接口定义

需要在 PDS 中重新建立
├── PGL50H 工程
├── PLL / 时钟资源
├── DDR3 IP
├── HDMI 板级接口
├── PGL50H 引脚约束
├── 时序约束
└── Bitstream / JTAG 下载流程
```

严禁在算法核心中深度绑定 Xilinx Clock Wizard、MIG、FIFO Generator 等专用 IP，否则会增加迁移工作量。

---

# 40. 项目最终主线总结

```text
第一步：视频链打通
HDMI → DDR → HDMI

第二步：预处理
Gray → Gaussian → Brightness / Gamma

第三步：核心矫正
Distortion → Pixel Fetch → Bilinear

第四步：轻量检测
Sobel → Threshold → Morphology → CCL

第五步：系统融合
Preprocess + Distortion + Detection

第六步：硬件优化
Fixed Point
+
Incremental Coordinate
+
Pixel Cache
+
Shared Window Buffer

第七步：定量评价
Image Quality
+
Distortion Error
+
FPGA Resource
+
FPS / Fmax
```

整个项目不依赖 YOLO，也可以做成一套完整、具有工程深度和比赛展示效果的 FPGA 视觉系统。

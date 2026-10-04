# MES50HP 资源与存储基线

## 1. 目标器件

```text
开发板：盘古50 MES50HP
FPGA：PGL50H-6IFBG484
系列：紫光同创 Logos
速度等级：-6
温度等级：工业级
封装：FBG484
```

## 2. FPGA 资源

根据 MES50HP 硬件使用手册，PGL50H-6IFBG484 的主要资源为：

| 资源 | 数量 | 项目主要用途 |
|---|---:|---|
| FF | 64,200 | 流水寄存器、状态机和缓存控制 |
| LUT6 | 42,800 | 定点加法、比较、地址生成和控制逻辑 |
| 18 Kbit DRM | 134 | 行缓存、FIFO 和 Local Pixel Cache |
| APM 乘法单元 | 84 | 畸变模型、增益和双线性插值 |
| PCIe Gen2 | 1 | 当前基础视频链不使用 |
| HSST | 4 路，最高 6.375 Gb/s | 当前基础视频链不使用 |

上述数量是器件资源上限，不是算法模块可独占资源。第一次资源规划至少为板卡接口、CDC、DDR3控制、调试逻辑和后续修改预留约15%的LUT/FF余量；APM和DRM配额以PDS综合结果为准。

Vivado综合只能检查可综合性和结构趋势，不能代替PGL50H的最终资源报告。

## 3. DDR3 拓扑

MES50HP核心板使用两颗DDR3器件：

```text
每颗容量：4 Gbit / 512 MB
每颗位宽：x16
组合位宽：x32
总容量：8 Gbit / 1 GB
最高时钟：400 MHz
数据速率：800 MT/s
理论峰值：25.6 Gbit/s = 3.2 GB/s
连接Bank：PGL50H Bank 3
```

两颗器件共同组成一个x32存储通道，不是两个可独立调度的DDR通道。Frame Buffer、Pixel Fetch和Cache都按一个共享存储通道规划。

理论峰值不能直接作为可用视频带宽。实际效率受以下因素影响：

- DDR3初始化与控制器配置；
- 突发长度；
- 行切换和Bank冲突；
- 读写仲裁；
- Pixel Fetch地址离散程度；
- FIFO和Cache命中率。

无板阶段先通过地址轨迹模型评估；上板后必须测量实际有效吞吐。

## 4. 视频接口

```text
HDMI输入：MS7200 Receiver
HDMI输出：MS7210 Transmitter
数字视频接口：24 bit RGB/YUV + PCLK + HS + VS + DE
配置接口：I²C
器件标称能力：HDMI 1.4b，最高4K@30
```

HDMI芯片的标称能力不等于当前FPGA工程能够直接实现4K处理。本项目仍按以下顺序推进：

```text
720P60 开发里程碑
    ↓
1080P30 最终基础目标
    ↓
1080P60 性能挑战
```

## 5. 项目资源策略

- Distortion Core优先控制APM数量和乘法流水深度；
- 3×3 Window Generator优先使用DRM推断的行缓存；
- 全帧缓存放在DDR3，不尝试放入片上DRM；
- Pixel Cache先通过软件评估命中率，再决定DRM容量；
- HDMI、DDR3和CDC逻辑计入板卡层预算；
- 每次PDS综合记录LUT6、FF、DRM、APM、Fmax和关键路径。

### 当前吞吐率基线（2026-10-03）

1080p30、100 MHz 算法时钟的帧周期预算为 3,333,333 cycles。RGBX8888
Tile Cache 当前板级配置为 **32 sets × 8 ways**：

| 项目 | 数值 |
|---|---:|
| Cache 数据容量 | 128 KiB |
| 1080p 整图仿真周期 | 3,237,697 cycles |
| 周期预算余量 | 95,636 cycles（2.9%） |
| DDR 行 burst 命令数 | 94,576 |

该结果来自单未完成读事务、首拍延迟和反压均已建模的 XSim 行为后端，且 RTL 输出已逐像素匹配固定点黄金帧。它证明当前算法侧的接口调度达到预算；**不**证明 PGL50H DDR3 PHY、仲裁器和 HDMI 并发时的物理吞吐率。上板前仍须以 PDS DRM/时序报告确认资源，实板阶段须测量真实 `rd_cmd_ready` 停顿和帧周期。

## 6. 资料来源

- 紫光同创盘古50K开发板介绍：<https://www.pangomicro.com/open/4276.html>
- MES50HP硬件使用手册：<https://szlogicmatrix.com/wp-content/uploads/2025/12/MES50HP%E5%BC%80%E5%8F%91%E6%9D%BF%E7%A1%AC%E4%BB%B6%E4%BD%BF%E7%94%A8%E6%89%8B%E5%86%8C_1V1.pdf>
- 2026竞赛选题指南：工作区中的《全国大学生嵌入式芯片与系统设计竞赛'2026FPGA赛道选题指南-紫光同创.pdf》

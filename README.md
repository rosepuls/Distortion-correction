# 盘古 200Pro+ FPGA 实时图像校正系统

本项目面向盘古 200Pro+（PG2L200H）开发板，以 1280×720、60 Hz 视频链路实现镜头畸变矫正、角度校正、运动平移补偿和自适应光照增强。视频经 HDMI 输入 FPGA，处理结果通过 HDMI 输出；上位机负责相机标定、运动估计和 UART 参数下发，主要像素处理在 FPGA 中完成。

## 当前最终项目：Stage13 720p60 运动防抖工程

**本仓库当前最终项目是 [`fpga/project/stage13_720p60_motion_stabilization_test/`](fpga/project/stage13_720p60_motion_stabilization_test/)。** 查看、构建或演示当前系统时，请优先使用此目录中的 PDS 工程、RTL、约束、构建脚本和配套说明。其他 `stage*` 目录是开发过程中的基线、对照或实验工程，不代表当前最终集成版本。

该工程从稳定的 720p60 图像增强基线发展而来，当前主数据路径为：

```text
HDMI 输入 → DDR 输入帧池 → 单应角度映射 → Brown-Conrady K3 畸变映射
          → 源坐标平移补偿 → DDR/Tile Cache 邻域读取 → 双线性插值
          → RGB 光照增强 LUT → DDR 输出帧池 → HDMI 输出
```

上位机脚本 [`host/pose/stage13_motion_stabilization.py`](host/pose/stage13_motion_stabilization.py) 从 OBS/UVC 帧估计全局平移，经过置信度筛选、路径低通与限幅后，通过 65 字节 UART 参数包发送补偿量。FPGA 校验参数，并在输出帧边界原子切换单应矩阵、平移量和增强曲线。平移补偿范围为每轴 ±24 像素，超出有效源图的边缘按现有黑边规则处理。

**验证范围：**现有记录确认，Stage13 的固定 UART `dx/dy` 参数接收、ACK、正负方向、帧边界切换及接近 ±24 像素的裁切已完成实板检查。连续视频中由上位机自动估计并补偿抖动的闭环效果仍需单独量化。Stage12 的 1080p 超分辨率和独立 SAD 运动估计器没有集成到这个最终工程；不要将其对应的实验结果当作 Stage13 的实板结果。详细状态见 [Stage13 工程 README](fpga/project/stage13_720p60_motion_stabilization_test/README.md) 与 [防抖记录](docs/chat/sports-stabilization.md)。

## 代码目录

| 目录 | 内容 |
| --- | --- |
| `fpga/project/stage13_720p60_motion_stabilization_test/` | 当前最终 FPGA 工程：PDS、RTL、IP、约束、仿真、构建脚本及调试配置 |
| `fpga/project/` 中的其他工程 | 各阶段基线、功能对照和独立实验工程 |
| `fpga/rtl/`、`fpga/sim/`、`sim/` | 共用 RTL、仿真脚本和参考测试内容 |
| `host/calibration/` | 相机标定、参数包与定点参数导出 |
| `host/pose/` | 角度跟踪、运动估计、光照选择和 UART 控制 |
| `host/reference/`、`host/verification/` | 软件参考和输入/输出图像测量工具 |
| `host/super_resolution/` | 独立的超分辨率研究代码；不属于当前最终 720p60 数据路径 |
| `docs/` | 设计计划、开发记录和结果说明 |

## 打开与构建当前工程

在 PDS 2022.2-SP6.4 中打开 `fpga/project/stage13_720p60_motion_stabilization_test/HDMI_IN_DDR3_HDMI_OUT.pds`。该工程的顶层器件、IP、RTL 和约束文件均保存在相同工程目录下。具体构建与下载步骤见工程内的 `README.md`、`README_JTAG.md` 和 `Build-UartParameterTest.ps1`。

本源码提交包保留工程源码、IP、配置和脚本，并附带当前 Stage13 的 `.sbit` 与配套 `.fic`。综合数据库、布局布线中间文件、历史位流、训练视频、采集图像和 Python 虚拟环境未收录；需要时可从源码重新运行相应构建或实验。下载位流时，应使用同一工程 `generate_bitstream/` 中配对的 `.sbit/.fic`。

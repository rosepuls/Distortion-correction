# Stage 4 畸变算法上板测试工程

日期：2026-10-21

## 测试目标

在真实相机标定和 DDR Tile Cache 接入前，先用片上可重复源图验证以下阶段 4 路径：

```text
720p60 输出扫描
  -> 固定径向 Q16.16 映射
  -> 坐标 FIFO
  -> 双线性 2×2 采样规划与常量黑边
  -> 片上 RGBX8888 网格/渐变源图
  -> 双线性插值
  -> HDMI 输出
```

固定径向公式为：

```text
source = output + (output - center) * r² / 2²³
```

它用于制造可观察的弯曲网格和边缘黑区，不代表工业相机的标定参数。

## 工程和位流

- PDS 工程：`fpga/project/stage4_algorithm_demo/`
- 生成脚本：`fpga/project/New-Stage4AlgorithmDemoProject.ps1`
- 完整构建脚本：`fpga/project/Run-Stage4AlgorithmDemo.ps1`
- 位流：`fpga/project/stage4_algorithm_demo/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`
- 位流大小：9,188,552 字节
- SHA-256：`A819A70B952582DECEAB21FA00D038917911A7BA9450EE153D1051434E8B7A97`

Stage 3 门控修正版和阶段 2 稳定版均未修改。Stage 4 工程保留原板级 PLL、HDMI 初始化、DDR3 IP 和引脚约束；DDR3 完成初始化，但算法演示包装器不发出 AXI 读写事务。

## 仿真结果

- Python 软件参考：径向坐标、程序化源图、二维小数插值和黑边均通过字面量测试。
- 单模块：径向映射、四邻点读取、采样规划和 RGBX8888 插值通过。
- 链路：随机周期反压下，中心、整数点、水平小数点、二维小数点和黑边点依次正确返回。
- 板级包装器：小帧扫描完整，AXI 请求保持关闭，LED 里程碑正确。
- 完整帧：1280×720 共 921,600 个像素连续有序；首点和末点为黑色，中心为白色网格交点；无输入停顿和序号错误。

## PDS 结果

- 工具：PDS 2022.2-SP6.4
- 器件：PG2L200H-6-FBB676
- 编译、综合、器件映射、布局布线、时序分析和位流生成均成功。
- 时序：`All Constraints Met`
- 74.2501 MHz HDMI 输出像素域：估算最高频率 84.3384 MHz，建立时间裕量 1.611 ns。
- Stage 4 `fram_buf`：503 LUT、562 FF、9 个分布式 RAM、22 个 APM。

## 上板预期

预期图像见 `docs/results/stage4-algorithm-demo-preview.png`。画面应为彩色渐变和白色 64 像素网格，网格向边缘弯曲，四角出现平滑的常量黑色边界。

LED4–LED7 定义：

| LED | 含义 | 稳定运行预期 |
| --- | --- | --- |
| LED4 | 检测到输出有效区输入 | 亮 |
| LED5 | 算法产生输出像素 | 亮 |
| LED6 | 完成至少一帧 | 亮 |
| LED7 | 输入停顿或像素序号错误 | 灭 |

烧录后检查 HDMI 输出为 1280×720@60 Hz，图案与预期图一致，LED4–LED6 亮且 LED7 灭。连续运行时记录黑屏、闪屏、错行、颜色错误和 LED7 状态。

## 后续接入边界

该位流证明片上阶段 4 算法及 HDMI 输出可实现、可布线并满足 74.25 MHz 时序。它尚未读取 HDMI 输入帧，也尚未验证 Tile Cache、DDR 源图访问、真实镜头模型或真实标定参数。下一步用 Tile Cache/DDR 读取器替换 `procedural_pixel_reader`，保持映射器、规划器、插值器和元数据接口不变。

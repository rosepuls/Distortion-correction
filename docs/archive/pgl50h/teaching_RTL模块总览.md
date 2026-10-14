# RTL 模块说明与系统位置

## 当前系统数据流

```text
输入像素流 / 测试图
    │
    ├─ 畸变坐标链：coordinate_gen → distortion_core_optimized
    │                                      │
    │                                      ▼
    │                         pixel_fetch_engine → bilinear_interp
    │
    ▼
校正后的 RGB 像素流
    │
    ├─ rgb2gray → brightness_gain → gamma_lut
    ├─ line_buffer_3x3 → window_3x3 → gaussian_3x3
    └─ sobel_3x3 → threshold → morphology
```

目前尚未存在真正的系统顶层 `top.sv`。现有文件由可独立测试的算法模块、存储接口模块和未来板级模块规划组成。

## 畸变校正坐标链

| 文件 | 作用 | 系统位置 |
|---|---|---|
| `distortion/coordinate_gen.sv` | 产生输出像素坐标 `(u, v)` 及 `valid/sof/eol`。 | 畸变校正坐标入口。 |
| `distortion/normalize.sv` | 将像素坐标归一化为相机坐标。 | 仅供基准 `distortion_core.sv` 使用。 |
| `distortion/distortion_core.sv` | 原始大位宽 Brown-Conrady 畸变计算实现。 | 对照版本，不建议作为最终实现。 |
| `distortion/distortion_core_optimized.sv` | Q18 优化版畸变核心，输出源图坐标、插值小数和四邻域有效标志。 | 当前推荐畸变计算实现。 |
| `distortion/coordinate_split.sv` | 将 Q13.19 源坐标拆为 `x0/y0/dx/dy`，并判断四邻域是否有效。 | 两种畸变核心的公共尾部。 |

## 图像存储与双线性插值

| 文件 | 作用 | 系统位置 |
|---|---|---|
| `memory/pixel_fetch_if.sv` | 定义逻辑像素地址的读请求/响应接口；不是 DDR 控制器。 | 畸变坐标与存储模块的接口边界。 |
| `memory/pixel_fetch_engine.sv` | 根据 `x0/y0` 请求 `p00/p10/p01/p11` 四个像素，驱动双线性插值。 | 畸变校正的数据取数阶段。 |
| `interpolation/bilinear_interp.sv` | 使用四邻域和 `dx/dy` 重采样；无效坐标输出黑像素。 | 畸变校正后的像素输出。 |

## 预处理与边缘检测

| 文件 | 作用 | 系统位置 |
|---|---|---|
| `preprocess/rgb2gray.sv` | RGB 转灰度。 | 视觉处理链入口。 |
| `preprocess/brightness_gain.sv` | 亮度增益调整。 | 图像增强。 |
| `preprocess/gamma_lut.sv` | Gamma 查表校正。 | 图像增强。 |
| `preprocess/line_ram_1r1w.sv` | 单读单写行缓存 RAM 抽象。 | 3×3 窗口的底层存储。 |
| `preprocess/line_buffer_3x3.sv` | 缓存前两行像素，提供三行时序数据。 | 3×3 邻域生成前级。 |
| `preprocess/window_3x3.sv` | 组成完整 3×3 像素窗口。 | Gaussian 与 Sobel 的共同输入。 |
| `preprocess/gaussian_3x3.sv` | 3×3 高斯滤波，抑制噪声。 | Sobel 前预滤波。 |
| `detect/sobel_3x3.sv` | 计算梯度/边缘强度。 | 边缘检测。 |
| `detect/threshold.sv` | 将边缘强度二值化。 | 二值边缘输出。 |
| `detect/morphology.sv` | 形态学去噪或连接边缘。 | 检测结果后处理。 |

## 板卡与验证文件

| 文件 | 作用 |
|---|---|
| `board/mes50hp/README.md` | 规划 MES50HP/PGL50H 的顶层、时钟复位、相机、DDR 与显示模块；当前不含具体板级实现。 |
| `xsim_simulation_guide.md` | XSim 仿真命令与说明，不参与综合。 |
| 各目录 `.gitkeep` | 保留目录，不参与硬件功能。 |

## 当前集成边界

- `distortion_core_optimized.sv` 已通过 Q18 Python 黄金向量对拍、XSim 回归和 PDS 综合。
- `pixel_fetch_engine.sv` 已定义从畸变坐标到四邻域像素读取的逻辑，但尚未连接真实 DDR 或帧缓存。
- `board/mes50hp/` 仍是板级接口规划；相机接收、DDR 帧缓存、HDMI 输出和系统顶层待实现。

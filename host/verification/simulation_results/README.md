# 角度矫正与运动防抖离线仿真（2026-11-03）

运行命令：

```powershell
Set-Location 'C:\Study\IC_Study\Project\FPGA\Contest\Pango_Micro_FPGA\Distortion-correction'
.\.venv\Scripts\python.exe host\verification\simulate_rotation_stabilization.py
```

完整数值见 [`summary.json`](summary.json)；逐角度结果见 [`rotation_metrics.csv`](rotation_metrics.csv)，逐帧防抖轨迹见 [`motion_trajectory.csv`](motion_trajectory.csv)。脚本使用固定随机种子 20261103，运行无需相机、采集卡或 FPGA。图表使用 matplotlib 导出为 300 dpi PNG，可直接插入 Word。

## 可插入 Word 的图

| 图号 | 文件 | 建议图注 |
|---|---|---|
| 图 1 | [`figure_1_rotation_examples.png`](figure_1_rotation_examples.png) | 合成棋盘在 −20°、0°、+20° 的输入画面及软件矫正画面对照。黑角为旋转重采样后的无效区域。 |
| 图 2 | [`figure_2_rotation_metrics.png`](figure_2_rotation_metrics.png) | 角度估计、估计误差、输出残余倾角和 2×2 采样有效面积随角度变化。 |
| 图 3 | [`figure_3_motion_time_series.png`](figure_3_motion_time_series.png) | 合成周期平移扰动的 X/Y 轨迹及补偿前后轨迹方差。 |
| 图 4 | [`figure_4_motion_xy_path.png`](figure_4_motion_xy_path.png) | 合成背景特征的二维位移轨迹；蓝色为理想采样模型的补偿后轨迹。 |

另外，各角度的原始输入和矫正后 PNG 以 `rotation_<序号>_<角度>deg_input/corrected.png` 命名，可单独选用。图表标题用英文以避免 Word 换机时中文字体替换；本报告中的中文图注可直接粘贴到文档。

## 方法与结果

| 项目 | 合成条件 | 结果 |
|---|---|---|
| 角度 | 1280×720、9×6 内角点棋盘，依次 0°、−20°、−10°、−5°、+5°、+10°、+20°、回零；零畸变；每个角度另做一次高斯模糊 σ=0.6 px 与 8 位像素噪声 σ=3 的估计 | 理想图最大绝对估计误差 0.0017°；模糊加噪声图最大绝对估计误差 0.0037°；量化矩阵经软件逆向采样后，最大残余倾角 0.0052° |
| 有效面积 | 理想旋转后的源坐标落在 2×2 采样域内 | ±5° 约 95.15%；±10° 约 91.05%；±20° 约 84.37% |
| 防抖 | 640×360 固定种子的合成纹理，10 Hz、120 帧；X 为幅度 6 px、频率 1.1 Hz 与幅度 2 px、频率 0.45 Hz 的正弦叠加，Y 为幅度 4 px、频率 0.9 Hz 的正弦；实际调用 LK 光流及 `alpha=0.18`、单轴限幅 ±24 px 的滤波器；方差统计去除起始 10 帧 | 输入轨迹方差 27.8382 px²；补偿后 2.9440 px²；降低 89.42%；光流中位单步误差 0.0321 px；无效估计 0 |

角度流程逐项执行棋盘检测、零位角度相减、矩阵生成、Q16.16/Q2.30 量化、Stage8 数值范围检查、软件逆向采样以及输出棋盘残余倾角测量。有效面积使用输出像素映射到输入 2×2 采样域的严格边界计算。防抖流程逐帧生成已知位移，调用现有 LK 光流估计，再将估计位移送入现有 `ShakeOnlyCompensator`，以「真实输入位移 − 下发补偿」计算理想输出轨迹。这些结果表明现有上位机算法在该组受控合成条件下能识别角度并减少周期性平移抖动。

**适用范围：**这不是 FPGA RTL 仿真或实板 HDMI 验收。除角度图的单次模糊与像素噪声试验外，模型没有模拟镜头畸变、棋盘遮挡、复杂噪声、前景运动、采集卡丢帧、UART 时序与 ACK、FPGA 参数生效时刻、DDR 访问或显示延迟。每角度的模糊噪声结果只有一次固定种子样本，不能视为统计置信区间。上表不能作为板上实际残余角度、稳像提升百分比或实时帧率的结论。此前实测 off/on 输入扰动不匹配，不能用这组理想仿真替代其板上对照。

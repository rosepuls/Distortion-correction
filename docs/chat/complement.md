# 验证补充材料：离线仿真、图像矫正实测与图像增强实测

> 给后续撰写技术文档的 AI：本页包含三组**证据性质不同**的材料。下面最先出现的“角度矫正与运动防抖”是 **2026-11-03 离线软件仿真**，全部图像和扰动由脚本生成，没有使用相机、OBS、采集卡、串口或 FPGA 实板；其数值不能写成板上验收结果。文末新增的“图像矫正实测”和“图像增强实测”来自 **真实 OBS 视频输入、FPGA HDMI 输出与采集卡截图**，并由上位机离线统计截图指标。增强实测还使用 UART 发送曲线编号并收到 ACK。实测图表由 Python 绘制，**绘图不等于硬件仿真**。写作时务必分别标明“离线仿真”或“实板采集后的图像分析”。

## 仿真的对象和流程

仿真入口是 [`host/verification/simulate_rotation_stabilization.py`](../../host/verification/simulate_rotation_stabilization.py)。脚本调用项目现有的棋盘角度估计、旋转单应矩阵构造与量化、LK 光流平移估计和 `ShakeOnlyCompensator` 防抖滤波函数。随机种子固定为 `20261103`，运行一次会重新生成下列数据和 300 dpi PNG 图。

### 角度矫正

脚本在 1280×720 画布上生成 9×6 内角点棋盘，按 **0° → −20° → −10° → −5° → +5° → +10° → +20° → 0°** 合成旋转输入。零位棋盘用于确定方向基线；每一角度检测棋盘角点、估计相对零位角度、生成输出到输入的旋转矩阵，将矩阵量化为上位机使用的 Q16.16/Q2.30 格式并检查 Stage8 数值范围。随后用 OpenCV 按量化矩阵执行软件逆向采样，再次检测矫正图的棋盘方向。

每个角度还生成一幅经高斯模糊（σ=0.6 px）和像素高斯噪声（σ=3 灰度级）处理的输入图，单独测一次角度估计。该组噪声试验每角度只有 **1 次固定种子样本**。仿真设镜头畸变为零，画面没有透视、遮挡和运动模糊。

| 指标 | 定义 | 本次结果及含义 |
|---|---|---|
| 理想图最大角度估计误差 | 8 个检查点中，`估计角度 − 设定角度` 的绝对值最大值 | **0.0017°**。表示合成棋盘角度检测在这 8 幅理想图上的最差偏差；不是转台或真实相机的测角精度。 |
| 模糊加噪声图最大角度估计误差 | 同上，但输入图额外加入上述模糊和噪声 | **0.0037°**。仅是这 8 幅噪声样本的最大值，不是统计置信区间。 |
| 软件矫正后最大残余倾角 | 对量化矩阵经 OpenCV 重采样所得的输出图，测棋盘方向相对零位的偏差；取 8 个检查点的最大绝对值 | **0.0052°**。表示理想软件图像路径中的残余倾斜；不能作为 FPGA HDMI 输出残余倾角。 |
| 理想有效图像面积 | 对每个输出像素检查映射到输入后是否满足 2×2 采样边界；有效像素占总输出像素的百分比 | 约 **95.15%（±5°）**、**91.05%（±10°）**、**84.37%（±20°）**。倾角越大，四角裁切区域越大；该值不包含实板边界填充和实际镜头畸变。 |

### 运动防抖

脚本生成固定种子的 640×360 纹理，共 **120 帧、10 帧/秒、12 秒**。X 方向叠加幅度 6 px/频率 1.1 Hz 和幅度 2 px/频率 0.45 Hz 的正弦位移；Y 方向是幅度 4 px/频率 0.9 Hz 的正弦位移。每对相邻帧通过项目现有 LK 光流求平移，送入 `ShakeOnlyCompensator`（`alpha=0.18`、每轴补偿上限 ±24 px）。仿真输出轨迹定义为 **已知真实输入位移减去算法给出的采样补偿**；该项没有调用 FPGA RTL，也没有生成并测量 HDMI 输出视频。

从第 11 帧起统计轨迹位置方差，即分别计算 X、Y 位置方差后相加，前 10 帧作为滤波起始段不计入。输入方差为 **27.8382 px²**，补偿后的理想轨迹方差为 **2.9440 px²**；比值为 **0.1058**，按 `1 − 2.9440 / 27.8382` 得到 **89.42% 的方差降低**。这里的“89.42%”只表示这组已知周期位移的轨迹位置波动降低，不表示真实画面的清晰度提高 89.42%，也不表示实板防抖率。光流估计的中位单步误差为 **0.0321 px**，本次无效估计数为 **0**；合成纹理清晰、背景占满画面，属于容易跟踪的条件。

## 四张可直接插入 Word 的图

全部图位于 `C:\Study\IC_Study\Project\FPGA\Contest\Pango_Micro_FPGA\Distortion-correction\host\verification\simulation_results\`，均为 300 dpi PNG。推荐在文档中保留“合成”“软件仿真”字样。

| 图 | 文件 | 推荐图注与读图说明 |
|---|---|---|
| 图 1 | [`figure_1_rotation_examples.png`](../../host/verification/simulation_results/figure_1_rotation_examples.png) | **合成棋盘角度矫正的输入与软件输出对比。** 左列为 −20°、0°、+20° 输入，右列为量化矩阵经 OpenCV 重采样后的输出。棋盘恢复水平；黑色角区表示映射超出输入范围的无效区域。 |
| 图 2 | [`figure_2_rotation_metrics.png`](../../host/verification/simulation_results/figure_2_rotation_metrics.png) | **合成角度序列的估计误差、输出残余倾角和有效面积。** 左上比较设定角度与估计角度；右上分别显示理想图与模糊加噪声图的估计误差；左下为软件输出残余倾角；右下为理想 2×2 采样有效面积。横轴按测试顺序排列，末点为回零。 |
| 图 3 | [`figure_3_motion_time_series.png`](../../host/verification/simulation_results/figure_3_motion_time_series.png) | **合成周期平移扰动的补偿前后轨迹。** 上两幅显示 X/Y 位移随时间变化；下图比较轨迹位置方差。本场景下方差降低 89.42%，蓝线依据已知输入位移和算法补偿计算。 |
| 图 4 | [`figure_4_motion_xy_path.png`](../../host/verification/simulation_results/figure_4_motion_xy_path.png) | **合成背景二维位移轨迹。** 橙线为输入位置，蓝线为按算法补偿计算的理想输出位置；蓝线更集中于零点附近。 |

逐角度输入与软件矫正图片另存为 `rotation_<序号>_<角度>deg_input.png` 和 `rotation_<序号>_<角度>deg_corrected.png`，可按需单张插入。

## 数据、复现与写作边界

| 文件 | 用途 |
|---|---|
| [`summary.json`](../../host/verification/simulation_results/summary.json) | 仿真元信息、逐角度指标、最大误差、防抖汇总和限制条件。 |
| [`rotation_metrics.csv`](../../host/verification/simulation_results/rotation_metrics.csv) | 逐角度设定值、估计值、误差、残余倾角和有效面积；用于制表。 |
| [`motion_trajectory.csv`](../../host/verification/simulation_results/motion_trajectory.csv) | 逐帧时间、输入位置、补偿量和补偿后位置；用于重画轨迹。 |
| [`simulation_results/README.md`](../../host/verification/simulation_results/README.md) | 更简短的图注和结果索引。 |

在 `Distortion-correction` 根目录运行：

```powershell
.\.venv\Scripts\python.exe host\verification\simulate_rotation_stabilization.py
```

脚本依赖项目虚拟环境中的 NumPy、OpenCV、pyserial、matplotlib。生成图像可直接用于“算法离线仿真”小节。**建议写法：**“在固定种子的合成棋盘和平移序列上，上位机角度估计与补偿算法按预期工作；理想图最大测角偏差为 0.0017°，OpenCV 软件矫正最大残余倾角为 0.0052°，指定周期抖动的轨迹方差降低 89.42%。这些结果只验证该离线模型与算法链路。”

**不能据此写为：**“FPGA 实板角度误差为 0.0017°”“HDMI 输出残余倾角为 0.0052°”“硬件防抖提升 89.42%”“UART/帧率已经验收”。仿真没有覆盖 RTL、串口收发与参数生效、DDR、HDMI 采集、帧延迟、真实镜头畸变、遮挡、明显前景运动或复杂场景。之前实测的 off/on 输入扰动也不匹配，不能把该仿真数值当成实测补充证据。

---

## 图像矫正实板采集与离线指标分析（2026-11-03）

### 实测了什么，哪些属于软件计算

把 `host/verification/0.png` 至 `7.png` 作为 OBS 输入测试图，经 FPGA 处理后，从 HDMI 转 USB 采集卡各保存一张 **1280×720** 的输出 PNG。采集、棋盘角点检测、边界黑区估计和工程性斜边 SFR 计算由 [`measure_hdmi_sfr.py`](../../host/verification/measure_hdmi_sfr.py) 执行。这里的“实测”指 **真实板卡 HDMI 画面被采集**；P95、黑边面积、SFR/MTF50 是对这些实拍图使用 OpenCV 作的**离线数值分析**，不是 RTL 仿真，也不是直接读取 FPGA 内部计数器。`--image-id` 只标注当前显示的原图编号，本身不会控制 OBS 切图。

使用 2026-11-03 20:02–20:06 的最新一组 0–7 截图；当天 19:54 左右更早的八张抓到了房间场景，**不用于下表和图表**。原始记录保存在 [`measurements.jsonl`](../../host/verification/capture_results/measurements.jsonl)，里面含两批记录；分析脚本按图号取最新记录。每张 FPGA 原始输出名为 `image_<图号>_<时间戳>_fpga.png`，位于 [`capture_results`](../../host/verification/capture_results)。分析数据另存于 [`image_correction/metrics.csv`](../../host/verification/analysis_20261103/image_correction/metrics.csv) 和同目录 `metrics.json`。

### 指标定义和结果

**棋盘直线度 P95（px）**：检测完整 9×6 内角点，把各行和各列的点分别拟合为直线，取所有点到对应直线距离的第 95 百分位；越小表示棋盘线条越直。原图与 FPGA 输出图用同一算法分别测量。`P95 降幅 = (原图 P95 − 输出 P95) / 原图 P95 × 100%`。这是静态图像几何直线度的对比，不能称为角度测量精度或任意场景的校正率。

| 图号 | 原图 P95 / px | FPGA 输出 P95 / px | P95 降幅 |
|---:|---:|---:|---:|
| 0 | 3.993 | 0.395 | 90.10% |
| 1 | 1.801 | 0.308 | 82.87% |
| 2 | 3.365 | 0.344 | 89.78% |
| 3 | 3.433 | 0.344 | 89.98% |

图 0–3 均检测到完整棋盘，输出 P95 为 0.308–0.395 px。原图是现成照片，FPGA 输出经过 OBS、HDMI 和采集卡链路；两端重采样和角点定位会影响数值，因此降幅只对这四组图及本次采集条件成立。

**黑边估计（%）**：统计 FPGA 输出中与图像边界相连的近黑像素（8 位灰度 ≤12），并根据对应原图尝试扣除本来就很暗的内容；是画面黑边的估计面积，不能当作 RTL 理论有效像素率。**SFR** 是所选斜边的归一化空间频率响应；**MTF50** 是 SFR 第一次下降穿过 0.5 时的频率，单位为 `cycles/captured-pixel`。本次 SFR 是工程估计，不是 ISO 12233 标准测试；不同图上的自然斜边不等价，不宜据 4、6、7 号的 MTF50 对画质作严格排名。

| 图号 | 黑边估计 / % | MTF50 / cycles/captured-pixel | 本次可用指标 |
|---:|---:|---:|---|
| 0 | 0.000 | — | 完整棋盘直线度 |
| 1 | 0.861 | — | 完整棋盘直线度 |
| 2 | 0.295 | — | 完整棋盘直线度 |
| 3 | 0.319 | — | 完整棋盘直线度 |
| 4 | 2.862 | 0.178 | 斜边 SFR/MTF50 |
| 5 | 2.689 | — | 仅截图和黑边估计；直线度、SFR 均不可用 |
| 6 | 0.044 | 0.216 | 斜边 SFR/MTF50 |
| 7 | 0.983 | 0.091 | 斜边 SFR/MTF50 |

黑边估计可能受原图暗内容和几何位置变化影响。图 5 的 `status=partial` 不应写成“所有图像质量指标通过”。

### 图表、图注和文件位置

下列 PNG、CSV 和解释报告均位于 `C:\Study\IC_Study\Project\FPGA\Contest\Pango_Micro_FPGA\Distortion-correction\host\verification\analysis_20261103\image_correction\`。图表由 [`analyze_20261103_results.py`](../../host/verification/analyze_20261103_results.py) 对实拍截图计算指标，再由 [`plot_20261103_results.py`](../../host/verification/plot_20261103_results.py) 绘制；两脚本处理已有数据，不生成合成 FPGA 图像。

| 文件 | 建议图注／用途 |
|---|---|
| [`01_grid_straightness.png`](../../host/verification/analysis_20261103/image_correction/01_grid_straightness.png) | **四张棋盘测试图的原图与 FPGA 输出直线度 P95。** 横轴为测试图 0–3，纵轴为点到拟合直线的 P95 距离（px，越低越直）；灰柱是原图，蓝柱是采集到的 FPGA 输出。 |
| [`02_black_border.png`](../../host/verification/analysis_20261103/image_correction/02_black_border.png) | **八张 FPGA 输出图的边界黑区估计。** 横轴为测试图号，纵轴为输出画面面积百分比；该量不是理论有效图像面积。 |
| [`03_sfr_curves.png`](../../host/verification/analysis_20261103/image_correction/03_sfr_curves.png) | **图 4、6、7 所选斜边的工程性 SFR 曲线。** 横轴是捕获像素的空间频率，纵轴为归一化 SFR；虚线 0.5 用于读出 MTF50。不同图的边缘材质和条件不统一。 |
| [`report.md`](../../host/verification/analysis_20261103/image_correction/report.md) | 单独的图像矫正说明、逐图指标与限制，可供后续 AI 写作时引用。 |

---

## 图像增强曲线的实板输出分析（2026-11-03）

### 实测了什么，哪些属于软件计算

固定房间场景下，依次通过 [`Run-UartEnhancementProfile.ps1`](../../fpga/project/stage11_720p60hz_adaptive_image_enhancement_test/sim/Run-UartEnhancementProfile.ps1) 下发曲线编号 0–4，收到协议、序号、状态、CRC 和回显内容校验通过的 ACK，随后各保存一张 OBS 输入和 FPGA 输出。每条曲线只有**一对静态帧**，两路截图时间相差约 0.74–0.83 秒。该组包含真实串口收发及 FPGA HDMI 画面；平均灰度与 P90 是对截图进行的上位机离线计算，**不属于仿真画面**。ACK 证明请求被接收，不单独证明活动参数组版本；输出亮度随编号变化为曲线作用提供画面证据。

**关键数据身份修正：**采集这五组图时，设备索引在配置文件中写反。原始 [`captures.jsonl`](../../host/verification/enhancement_profiles/captures.jsonl) 和文件名 `*_hdmi.png` 实际对应 **OBS 输入、索引 3**；文件名 `*_obs.png` 实际对应 **FPGA HDMI 输出、索引 2**。分析脚本已按设备实测身份读取，原始图片没有改名。后续写作不可照旧文件名直接断言输入/输出。

### 指标定义和结果

**平均灰度 Y**：使用 OpenCV 将 BGR 转为 8 位灰度，再计算整帧像素平均，范围 0–255；数值越高表示整帧越亮。**输出相对曲线 0**为 `该曲线 FPGA 输出平均灰度 − 曲线 0 FPGA 输出平均灰度`，单位是 8 位灰度级。该差值在同一路 FPGA 输出之间比较，可避开两路设备基准亮度不同的问题。**P90** 是灰度像素的第 90 百分位，用来描述较亮区域的水平；P90=255 表示至少约 10% 的像素达到最高灰度值，存在高亮饱和风险，不能推断丢失细节可被恢复。

| 曲线 | 预期用途 | OBS 输入均值 | FPGA 输出均值 | 输出相对 0 / 灰度级 | OBS 输入 P90 | FPGA 输出 P90 |
|---:|---|---:|---:|---:|---:|---:|
| 0 | 关闭增强 | 156.535 | 175.881 | 0.000 | 208 | 229 |
| 1 | 夜间提亮 | 156.537 | 217.187 | +41.306 | 208 | 252 |
| 2 | 强夜间提亮 | 156.730 | 236.929 | +61.048 | 209 | 255 |
| 3 | 高光压缩 | 157.710 | 155.873 | −20.008 | 209 | 206 |
| 4 | 强高光压缩 | 157.408 | 126.382 | −49.499 | 210 | 172 |

OBS 输入均值仅在 156.535–157.710 内变化（范围 1.175），FPGA 输出则按曲线类别明显提亮或压暗。曲线 2 比 1 提亮更强；曲线 4 比 3 压暗更强。曲线 0 的 OBS/FPGA 绝对亮度本来就不同，不能把其差值直接归因于 0 号 LUT。上述结果只验证该固定场景的一次抓帧响应；没有重复样本、受控曝光、逐像素配准或时间序列，不能据此给出误差条、统计显著性、动态稳定性或所有场景画质收益。曲线 5 没有成组实测帧，本节不报告曲线 5 的板上指标。

### 图表、图注和文件位置

以下文件位于 `C:\Study\IC_Study\Project\FPGA\Contest\Pango_Micro_FPGA\Distortion-correction\host\verification\analysis_20261103\image_enhancement\`，原始截图位于 [`enhancement_profiles`](../../host/verification/enhancement_profiles)。`metrics.csv` 明确给出修正后的 `input_png_actual` 与 `output_png_actual`，可据此找图，不要按旧文件名猜测设备身份。

| 文件 | 建议图注／用途 |
|---|---|
| [`01_mean_brightness.png`](../../host/verification/analysis_20261103/image_enhancement/01_mean_brightness.png) | **曲线 0–4 的 OBS 输入和 FPGA 输出整帧平均灰度。** 横轴为曲线编号，纵轴为 0–255 的 8 位灰度均值；灰柱为输入，橙柱为输出。 |
| [`02_output_change_vs_bypass.png`](../../host/verification/analysis_20261103/image_enhancement/02_output_change_vs_bypass.png) | **FPGA 输出相对 0 号关闭增强的平均灰度变化。** 正值表示更亮，负值表示更暗；它是同一输出设备的逐曲线对比。 |
| [`03_highlight_p90.png`](../../host/verification/analysis_20261103/image_enhancement/03_highlight_p90.png) | **曲线 0–4 的输入与输出亮区 P90。** 曲线 2 输出 P90 达 255；曲线 3、4 把输出亮区分位值降至 206 和 172。 |
| [`metrics.csv`](../../host/verification/analysis_20261103/image_enhancement/metrics.csv) | 逐曲线序号、均值、P10/P90、暗区与高亮占比，以及修正后的实际输入/输出图片路径。 |
| [`report.md`](../../host/verification/analysis_20261103/image_enhancement/report.md) | 单独的图像增强说明与写作限制。 |

### 给后续技术文档的边界提示

可以写“在这组固定场景的实板采集中，棋盘图 0–3 的输出直线度 P95 小于对应原图，且增强曲线 1–4 的 FPGA 输出亮度相对 0 号出现预期方向变化”。不得把本节写成“RTL 仿真验证”“ISO 12233 认证”“八张图的 SFR 全部通过”“曲线 5 已实测”“增强画质在所有场景更好”或“动态帧率/稳定性已验收”。本页前半部分的角度、防抖离线仿真数字也不能混入这些 FPGA 实板图像指标。

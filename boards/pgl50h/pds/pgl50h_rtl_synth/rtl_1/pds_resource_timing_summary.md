# PGL50H RTL 单模块综合资源与时序汇总

## 工程与约束信息

| 项目 | 记录 |
|---|---|
| PDS 版本 | PDS / Fabric Compiler 2022.2-SP6.4（build 146967） |
| 器件 | 紫光同创 PGL50H，速度等级 -6，封装 FBG484 |
| 时钟约束 | `create_clock -name clk -period 20.000 [get_ports {clk}]` |
| 约束基准 | 20 ns，即 50 MHz；这是器件级时钟约束，不是开发板实测频率 |
| 统计范围 | 各 RTL 模块分别作为顶层进行综合；不是将整条图像处理链连接后的总资源 |
| 资源口径 | PDS 综合报告中的 LUT、Registers、DRM18K、APMs |
| 时序口径 | 各模块 `place_route/*_timing_summary_after_hold_fix.txt` 的 Slow Corner setup WNS |

## 单模块结果

| 模块 | LUT | FF | DRM18K | APM | 慢角 WNS / 裕量 (ns) | 估算 Fmax (MHz) | 综合 / 时序备注 |
|---|---:|---:|---:|---:|---:|---:|---|
| `rgb2gray` | 33 | 11 | 0 | 1.5 | — | — | 摘要未列出 setup endpoint；不能据此推断 Fmax |
| `brightness_gain` | 37 | 37 | 0 | 1.0 | 13.173 | 146.5 | All Constraints Met |
| `gamma_lut` | 17 | 18 | 1 | 0 | 18.323 | 596.3 | All Constraints Met |
| `bilinear_interp` | 248 | 27 | 0 | 12.0 | — | — | 摘要未列出 setup endpoint；不能据此推断 Fmax |
| `line_buffer_3x3` | 118 | 87 | 2 | 0 | 16.211 | 263.9 | All Constraints Met；已包含其推断出的行缓存 DRM |
| `window_3x3` | 141 | 193 | 0 | 0 | 15.241 | 210.1 | All Constraints Met |
| `gaussian_3x3` | 80 | 11 | 0 | 0 | — | — | 摘要未列出 setup endpoint；不能据此推断 Fmax |
| `sobel_3x3` | 139 | 15 | 0 | 0 | — | — | 摘要未列出 setup endpoint；不能据此推断 Fmax |
| `threshold` | 21 | 16 | 0 | 0 | 17.034 | 337.1 | All Constraints Met |
| `morphology` | 7 | 5 | 0 | 0 | 19.035 | 1036.3 | All Constraints Met；仅 1 个 setup endpoint，频率估算参考性较低 |

## 读数说明

- 估算 Fmax 由慢角 WNS 作一阶换算：`Fmax ≈ 1000 / (20 ns - WNS)` MHz。它只是当前约束和实现结果下的内部寄存器路径估算，不是板上实测，也不等同于完整系统可运行频率。
- `—` 表示时序摘要没有报告受约束的 setup endpoint。即便摘要顶部写有 `All Constraints Met`，对于没有被分析的路径也不能据此给出时序裕量或 Fmax。
- 当前约束只定义了 `clk` 周期，没有为输入/输出加入延迟约束；日志中未约束的端口按组合输入/输出处理。因此这些结果不能替代完整的视频接口时序约束或板级验证。
- 每行是独立顶层综合的结果，不应将各行资源直接相加来代表集成系统资源；集成后共享逻辑、连线和层级优化都会改变资源用量。
- PDS 资源统计中 `FF` 对应报告的 `Total Registers`；APM 可出现小数（如 1.5），此处保留工具报告值。

## 报告来源

- 工程版本、器件与源文件配置：`../pgl50h_rtl_synth.pds`
- 时钟约束：`../source/clk.fdc`
- 各模块综合资源与布局布线时序：来自生成本汇总时的 PDS 综合和布局布线报告。

PDS 的原始数据库、网表和逐次运行日志均为可再生构建产物，已由 `.gitignore` 排除；需要复核或更新本表时，请使用上述项目定义和约束重新运行相应流程。


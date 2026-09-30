# 定点数值规范

## 1. 目的

本文档统一项目中的位宽、符号、Q 格式、移位、截断、舍入、溢出和饱和规则。Python Bit-accurate Model 与 RTL 必须执行完全相同的数值操作。

Float Model 用于验证数学公式和图像效果；Bit-accurate Model 才是 RTL 逐位比较的直接参考。

---

## 2. Q 格式记法

本项目约定：

```text
signed QI.F
```

其中：

- 总位宽为 `I+F`；
- `I` 包含符号位；
- `F` 为小数位数；
- 实际数值等于补码整数除以 `2^F`。

例如 `signed Q4.28`：

```text
总位宽 = 32 bit
整数区域 = 4 bit（含符号位）
小数区域 = 28 bit
近似范围 = [-8, 8)
```

`unsigned Q0.16` 表示 16 bit 纯小数，范围为 `[0,1)`。

所有文档和代码都使用这一解释，避免不同 Q 格式命名习惯造成一位偏差。

---

## 3. 全局数值规则

### 3.1 显式位宽

- 禁止依赖 Verilog 表达式的隐式位宽扩展；
- 常量必须明确位宽和符号；
- 有负数的差分、系数和累加器必须显式声明为 `signed`；
- 乘法结果先保留完整理论位宽，再按规范缩位；
- 加法前必须把操作数扩展到相同位宽。

### 3.2 第一版舍入基线

第一版采用直接右移截断：

```text
scaled = value >>> FRACTION_BITS
```

对于有符号补码，算术右移保留符号。Python Bit-accurate Model 必须模拟相同的补码宽度和算术右移行为。

四舍五入只作为后续优化选项。若启用，必须同时修改：

- 本规范；
- Bit-accurate Model；
- RTL；
- 测试向量。

### 3.3 饱和规则

8 bit 图像输出统一饱和：

```text
value < 0     → 0
value > 255   → 255
otherwise     → value[7:0]
```

除非模块规范明确允许回绕，否则不能直接截取低 8 bit 作为输出。

### 3.4 溢出规则

- 中间结果默认不允许静默溢出；
- Bit-accurate Model 记录每个节点的最小值、最大值和溢出次数；
- Testbench 在关键中间结果超出设计范围时报告失败；
- 只有经过误差分析确认的节点才允许主动截位。

---

## 4. 基础图像模块格式

### 4.1 RGB 转灰度

公式：

\[
Gray=(77R+150G+29B)\gg 8
\]

第一版位宽：

| 数据 | 符号与位宽 | 说明 |
|---|---|---|
| `R/G/B` | unsigned 8 bit | 范围 0–255 |
| `77R` | unsigned 15 bit | 最大 19635 |
| `150G` | unsigned 16 bit | 最大 38250 |
| `29B` | unsigned 13 bit | 最大 7395 |
| 加权总和 | unsigned 16 bit | 最大 65280 |
| `Gray` | unsigned 8 bit | 总和右移 8 bit |

由于系数之和为 256，输入全 255 时输出恰好为 255。

### 4.2 Brightness / Gain

公式：

\[
Y_{out}=\alpha Y_{in}+\beta
\]

初始格式：

| 数据 | 格式 | 说明 |
|---|---|---|
| `Y_in` | unsigned 8 bit | 0–255 |
| `alpha` | unsigned Q4.12，16 bit | 第一版非负增益 |
| `beta` | signed 10 bit integer | 建议配置范围 -256–255 |
| `alpha × Y_in` | unsigned 24 bit，12 小数位 | 保留完整乘积 |
| 累加器 | signed 25 bit，12 小数位 | 加入 `beta << 12` |
| `Y_out` | unsigned 8 bit | 右移 12 bit 后饱和 |

配置层可以进一步限制实际增益范围，例如 0–4，以降低误配置风险。

### 4.3 Gamma LUT

| 数据 | 格式 |
|---|---|
| LUT 地址 | unsigned 8 bit |
| LUT 数据 | unsigned 8 bit |
| LUT 深度 | 256 |

Gamma 表由 Python 生成。RTL 不执行实时指数运算。

### 4.4 Gaussian 3×3

核系数和为 16。9 个 unsigned 8 bit 像素加权和最大为：

```text
255 × 16 = 4080
```

因此：

| 数据 | 格式 |
|---|---|
| 输入像素 | unsigned 8 bit |
| 加权和 | unsigned 12 bit |
| 输出像素 | unsigned 8 bit，右移 4 bit |

### 4.5 Sobel

单方向理论范围：

```text
Gx, Gy ∈ [-1020, 1020]
```

第一版格式：

| 数据 | 格式 |
|---|---|
| `Gx/Gy` | signed 12 bit |
| `abs(Gx)/abs(Gy)` | unsigned 11 bit |
| `G=abs(Gx)+abs(Gy)` | unsigned 12 bit |
| 显示或阈值输入 | 保留 12 bit |
| 8 bit 可视化结果 | 饱和到 255 |

阈值模块优先直接使用 12 bit 梯度，避免过早饱和损失检测信息。

### 4.6 Morphology

二值图内部统一使用 1 bit：

```text
0 = background
1 = foreground
```

只有显示时才扩展为 `0/255` 的 8 bit 像素。

---

## 5. Bilinear 格式

公式：

\[
P_t=P_{00}+(P_{10}-P_{00})d_x
\]

\[
P_b=P_{01}+(P_{11}-P_{01})d_x
\]

\[
P=P_t+(P_b-P_t)d_y
\]

初始格式：

| 数据 | 格式 | 说明 |
|---|---|---|
| `P00/P10/P01/P11` | unsigned 8 bit | 0–255 |
| `dx/dy` | unsigned Q0.16 | `[0,1)` |
| 水平像素差 | signed 9 bit | -255–255 |
| 水平乘积 | signed 25 bit | 16 小数位 |
| `Pt/Pb` 工作值 | signed 26 bit | 保留 16 小数位 |
| `Pb-Pt` | signed 27 bit | 保留 16 小数位 |
| 垂直乘积 | signed 43 bit | 32 小数位 |
| 最终工作值 | signed 44 bit | 32 小数位 |
| 输出 | unsigned 8 bit | 缩放后饱和 |

实现时可以经过范围证明缩减位宽，但第一次正确性版本先保留完整乘积，不在未分析的中间级提前丢位。

RGB 三通道使用相同的 `dx/dy`，第一版并行计算，三个通道执行完全相同的截断和饱和规则。

---

## 6. 畸变坐标格式

第一版候选格式：

| 数据 | 初始格式 | 说明 |
|---|---|---|
| `u/v` | unsigned integer | 位宽由最大分辨率决定 |
| `cx/cy` | signed Q13.19 | 像素坐标 |
| `fx/fy` | signed Q13.19 | 像素单位焦距 |
| `inv_fx/inv_fy` | signed Q2.30 | 预计算倒数候选格式 |
| `x/y` | signed Q4.28 | 归一化坐标 |
| `k1/k2` | signed Q4.28 | 径向系数 |
| `p1/p2` | signed Q4.28 | 切向系数 |
| `r²/r⁴` | 完整乘积后按范围分析缩位 | 不预先强行统一格式 |
| `src_x/src_y` | signed Q13.19 | 源图像坐标 |
| `x0/y0` | signed integer | floor 后坐标 |
| `dx/dy` | unsigned Q0.16 | 插值小数部分 |
| `coord_valid` | 1 bit | 四邻域是否全部有效 |

注意：上述格式是 Bit-accurate Model 的扫描起点，不是未经验证的最终结论。

归一化不实现运行时通用除法器。配置软件预先计算：

```text
inv_fx = 1 / fx
inv_fy = 1 / fy
```

RTL 使用定点乘法完成：

```text
x = (u-cx) × inv_fx
y = (v-cy) × inv_fy
```

每个乘法节点先保留完整理论位宽。具体缩位位置必须由 Python 范围扫描与误差报告决定，并记录到本文件的后续版本中。

### 6.1 当前基准 RTL 契约

`rtl/distortion/distortion_core.sv` 使用上述格式实现 Brown-Conrady 二阶径向和切向项。输入配置端口统一为 32 bit signed；`cfg_fx_q19`、`cfg_fy_q19`、`cfg_cx_q19`、`cfg_cy_q19` 为 Q13.19，`cfg_inv_fx_q30`、`cfg_inv_fy_q30` 为 Q2.30，`cfg_k1_q28`、`cfg_k2_q28`、`cfg_p1_q28`、`cfg_p2_q28` 为 Q4.28。

核心从一次有效坐标输入到 `out_src_x_q19/out_src_y_q19/out_x0/out_y0/out_dx_q16/out_dy_q16/out_coord_valid` 的固定延迟为 5 个时钟周期；其前级 `coordinate_gen.sv` 另有 1 个寄存器级。二者级联时，输入 `valid/sof/eol` 到结果输出的固定延迟为 6 个时钟周期。有效 SOF 周期锁存全套相机配置，帧内配置端口变化不得影响已锁存帧。

---

## 7. 负坐标与 floor

`x0/y0` 必须采用数学 floor，不能把负数简单截断到 0：

```text
x0 = floor(src_x)
y0 = floor(src_y)
```

对于二进制定点补码，可使用算术右移取得 floor 结果。小数部分按下式生成：

```text
dx = src_x - (x0 << FRACTION_BITS)
dy = src_y - (y0 << FRACTION_BITS)
```

这样即使源坐标为负数，`dx/dy` 仍保持在 `[0,1)`。是否取像素由 `coord_valid` 单独判断。

---

## 8. 参数锁存与一致性

以下参数在帧首锁存，并在整帧保持不变：

```text
fx / fy / cx / cy
inv_fx / inv_fy
k1 / k2 / p1 / p2
brightness gain / offset
threshold
Gamma table bank selection
```

软件模型生成测试向量时，必须把参数配置随测试记录保存，确保结果可以复现。

---

## 9. 数值验证指标

每组格式至少统计：

```text
Maximum Coordinate Error
Mean Coordinate Error
Coordinate RMSE
Pixel MAE
Pixel MSE
PSNR
Out-of-bound Decision Mismatch Count
Saturation Count
Intermediate Overflow Count
```

RTL 接受标准：

- 对 Bit-accurate Model：有效输出必须逐位一致；
- 对 Float Model：误差必须记录，但不要求逐位一致；
- 任何允许的误差都必须来自已记录的量化步骤；
- 不允许出现来源不明的 1 LSB 偏差。

---

## 10. 模块数值检查表

每个模块进入 RTL 前必须明确：

- [ ] 每个端口的位宽和 signed 属性；
- [ ] 每个乘法器的完整输出位宽；
- [ ] 每个加法器的扩展位宽；
- [ ] 每一次移位的位置和方向；
- [ ] 截断还是四舍五入；
- [ ] 溢出是禁止、饱和还是显式回绕；
- [ ] 输出饱和范围；
- [ ] Python 中对应的逐位实现；
- [ ] 极值输入下的范围证明。

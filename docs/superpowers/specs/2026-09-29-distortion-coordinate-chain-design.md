# 畸变坐标链设计

## 目标与范围

实现与现有基础图像处理链兼容的畸变坐标链：固定点 Python 参考模型、输出像素坐标生成、归一化、Brown-Conrady 二阶径向/切向畸变、源坐标拆分，以及自动 RTL Testbench。该链只生成双线性插值所需的源坐标与合法标记；DDR Pixel Fetch、Cache 和实际 HDMI/DDR3 接口不在本次范围内。

## 文件与接口

新增或更新的文件如下：

```text
software/bitaccurate_distortion.py
rtl/distortion/coordinate_gen.sv
rtl/distortion/normalize.sv
rtl/distortion/distortion_core.sv
rtl/distortion/coordinate_split.sv
sim/tb_distortion_core.sv
```

`coordinate_gen` 使用项目已冻结的无反压流控制端口 `clk/rst_n/in_valid/in_sof/in_eol`，产生对应的整数输出坐标 `u/v`，并以一个寄存器级对齐输出控制信号。`distortion_core` 接收该坐标流，输出 Q13.19 的 `src_x/src_y`、整数 `x0/y0`、Q0.16 `dx/dy` 和 `coord_valid`，并保持 `out_valid/out_sof/out_eol` 与结果对齐。其帧配置输入在有效 `in_sof` 当周期锁存，且整帧稳定。

`normalize` 和 `coordinate_split` 是无厂商依赖的通用算术子模块，由 `distortion_core` 实例化。它们不引入隐藏状态，便于独立仿真和后续 PDS 推断验证。

## 定点数据流

| 节点 | 格式 | 规则 |
|---|---|---|
| `u/v` | unsigned integer | 输出像素坐标 |
| `fx/fy/cx/cy` | signed Q13.19 | 帧首锁存 |
| `inv_fx/inv_fy` | signed Q2.30 | 帧首锁存 |
| `x/y/k1/k2/p1/p2` | signed Q4.28 | 算术右移截断 |
| `r2/r4` | 完整乘积、按节点缩放 | 基准正确性实现优先 |
| `src_x/src_y` | signed Q13.19 | 反向映射源坐标 |
| `x0/y0` | signed integer | 算术右移取得数学 floor |
| `dx/dy` | unsigned Q0.16 | Q13.19 小数部分截为 16 位 |

数学模型为 Brown-Conrady 反向映射：先把输出坐标归一化，再计算 `r2`、`r4`、径向项和切向项，最后映射为源坐标。所有右移均为算术右移截断；不实行未记录的舍入。

## 流水线与边界

`distortion_core` 使用固定流水：归一化、平方与 `r2`、`r4`、径向/切向、源坐标、拆分与合法判断。该基准实现的目标是每拍接受一个坐标；固定延迟由 Testbench 依据实际级数检查。

`coordinate_split` 执行数学 floor，故负 Q13.19 坐标也会产生 `[0, 1)` 范围内的正确小数部分。只有 `0 <= x0 < IMAGE_WIDTH-1` 且 `0 <= y0 < IMAGE_HEIGHT-1` 时 `coord_valid=1`；否则后级应输出黑色且不发起像素请求。

## 验证

Python 测试覆盖零畸变、单位径向项、负坐标 floor、四邻点边界和整数双线性截断。RTL Testbench 会增加零畸变恒等映射、径向与切向用例、边界/负坐标、输入空拍、复位、连续两帧和帧间参数变更。每个 RTL 输出与 Python Bit-accurate 参考向量逐项比较，包括控制信号。

## 资源策略

初版保留足够的中间位宽以保证与模型一致，优先建立逐位正确性。完成范围/误差报告与 PDS 资源报告后，才允许在不改变端口语义的前提下缩位、重定时或替换为增量坐标实现。

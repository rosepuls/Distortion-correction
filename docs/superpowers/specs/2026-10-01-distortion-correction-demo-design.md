# 畸变矫正图片级演示设计

## 目标

以直线彩色棋盘图作为理想场景，先在 Python 中生成模拟相机畸变图，再将该畸变图
写入 DDR 行为模型，由现有 RTL 整链矫正。最终图像应明显恢复为接近笔直的棋盘，
同时 RTL 输出必须与 Python 定点 Golden 逐像素一致。

## 数据方向

```text
标准直线棋盘图
  -> Python 迭代求 Brown-Conrady 逆映射
  -> 模拟相机畸变输入图
  -> DDR 行为模型
  -> coordinate_gen -> distortion_core -> pixel_fetch_engine -> bilinear_interp
  -> RTL 矫正输出图
```

生成畸变输入时，对畸变图的每个像素坐标求解对应的无畸变坐标，再从标准棋盘图
双线性取样。不能简单把 `k1/k2/p1/p2` 取反，因为 Brown-Conrady 多项式的逆并不
等于系数取反。

## 固定配置

- 分辨率：256×192。
- 棋盘格：RGB，格宽 32 像素。
- 相机：`fx=fy=180.0`，`cx=127.5`，`cy=95.5`。
- 畸变：`k1=-0.25`，`k2=0.05`，`p1=0.001`，`p2=-0.001`。
- RTL 与 Python Golden 沿用项目冻结的定点格式和黑色边界策略。

## 文件隔离

- 反向映射脚本：`software/sim_assets/generate_distorted_input.py`。
- Testbench：`sim/tb_distortion_correction_image.sv`。
- 一键入口：`sim/run_distortion_correction_image.ps1`。
- XSim 临时目录：`xsim.dir/distortion_correction_image/`。
- 最终结果目录：`result/sim_assets/correction_full_chain_256x192/`。

对比图显示标准直线图、模拟相机畸变输入、RTL 矫正输出和 RTL/Golden 差分。

## 验收标准

1. 畸变输入的直线明显弯曲，RTL 输出明显恢复为直线。
2. XSim 输出 `TEST_PASS: distortion_correction_image`。
3. RTL 与 Python Golden 的 49,152 个 RGB888 像素逐位相同。
4. Python 完整回归无新增失败。

# 256x192 彩色畸变图片级仿真计划

## 目标

在无板卡阶段，以 256x192、32 像素格的 RGB 彩色棋盘图验证
`pixel_fetch_engine` 与 Python 定点畸变参考模型的端到端一致性。

## 固定输入与参数

- 图像：256x192 RGB 彩色棋盘格，方格边长 32 像素。
- 相机：`fx=fy=180.0`，`cx=127.5`，`cy=95.5`。
- 畸变：`k1=-0.25`，`k2=0.05`，`p1=0.001`，`p2=-0.001`。
- 边界：四邻域不完整时输出黑色，与 `bitaccurate_distortion.py` 一致。

## 执行步骤

1. 扩展棋盘图脚本，支持确定性的彩色棋盘图；为新资产添加单元测试。
2. 新建坐标向量生成器：调用 `bitaccurate_distortion.py`，输出 65 位
   `coord_valid/x0/y0/dx/dy` 向量和 RGB888 Golden 图 `.mem`。
3. 新建帧比较脚本及其单元测试，用于逐像素比较 Golden 与 RTL 输出。
4. 新建 `tb_pixel_fetch_distortion_image.sv`：顺序送入 256x192 坐标向量，
   检查颜色、SOF 和 EOL，并写出 RTL `.mem`。
5. 新建 PowerShell 入口：生成所有输入，运行 XSim 于
   `xsim.dir/pixel_fetch_distortion_image`，比较输出，并生成两张 PNG。
6. 运行 Python 测试和完整 XSim；仅在全部通过后报告生成的图像和结果。

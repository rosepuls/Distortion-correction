# 上位机工具

`calibration/` 保存棋盘格制作和相机标定工具；`reference/` 保存 OpenCV 同参数矫正、有效区域掩码和 RGBX8888 字格式导出工具。当前没有工业相机的真实标定照片，因此没有真实内参或矫正效果可报告。

## 1. 安装上位机依赖

在仓库根目录的 PowerShell 中运行：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r host\requirements.txt
```

当前系统的默认 Python 尚未安装 `cv2`。上述命令使用项目内的虚拟环境，不改动默认 Python。

## 2. 制作与拍摄棋盘格

已生成 [A4 横向、9×6 内角点、25 mm 格距棋盘格](calibration/board_9x6_25mm_A4.svg)。打印时选择 **100% / 实际尺寸**，关闭“适应纸张”，用尺实测任意数格的宽度；若实测与 25 mm 不符，就用实测格距作为标定输入。需要其他格数或尺寸时运行：

```powershell
python host\calibration\make_checkerboard_svg.py --cols 9 --rows 6 --square-mm 25 --out host\calibration\my_board.svg
```

在最终工业相机、镜头、对焦、分辨率和 UVC 模式下直接保存**原始 1280×720 相机帧**，不要用电脑桌面截图代替，也不要缩放或预先矫正。至少拍摄 20 张可检测照片，建议 25–30 张：棋盘格分别覆盖画面中心、四角与边缘，改变板的倾角和距离，避免连续保存几乎相同的姿态。保持棋盘格平整、清晰且完整可见，并另外保存未参与标定的直线图卡或棋盘格图作为参考图输入。记录相机型号或序列号、镜头、焦距、对焦状态及实际采集帧率。

## 3. 计算真实标定参数

将标定原图放在 `host/calibration/images/`，再运行：

```powershell
.\.venv\Scripts\python.exe host\calibration\calibrate.py --images host\calibration\images --cols 9 --rows 6 --square-mm 25 --out host\calibration\output --camera-id "实际相机型号"
```

`--cols`、`--rows` 是**内角点**，不是黑白格数量；`--square-mm` 必须与实物测量一致。输出 `calibration.json` 包含所有 OpenCV 畸变系数（包括 `k3`）、每张图的重投影误差、原图 SHA-256、拒收原因以及把 `k3` 置零造成的映射差异。若少于 20 张有效照片，工具会停止，不产出标定结果。

当 `k3` 置零的最大映射差异不超过项目设定的 0.5 像素时，可以另行导出旧 FPGA 几何核心的 32 位定点寄存器：

```powershell
.\.venv\Scripts\python.exe host\calibration\export_fixed_parameters.py --calibration host\calibration\output\calibration.json --out host\calibration\output\fixed_parameters.json
```

若差异超过阈值，脚本会拒绝导出并提示先扩展 FPGA 核心以支持 `k3`。导出文件记录 Q13.19 内参、Q2.30 焦距倒数、Q4.28 畸变系数及对应补码十六进制；**它不是 UART 参数包**，后续还需定义帧边界更新和 CRC。

## 4. 生成软件参考图

用一张未参与标定的原始 720p 相机照片运行：

```powershell
.\.venv\Scripts\python.exe host\reference\render_reference.py --calibration host\calibration\output\calibration.json --input "C:\path\to\held_out_frame.png" --out host\reference\output --rgbx-hex
```

输出 `undistorted.png`、`valid_mask.png` 和 `reference.json`；可选的 `undistorted_rgbx.mem` 每行一个 32 位数值字 `RRGGBB00`。掩码只标记四邻域均落在输入图内的像素，其他输出像素为黑色。默认输出相机矩阵与输入矩阵相同，匹配旧 FPGA 核心的单套内参接口；`--output-matrix optimal --alpha 1` 可另外生成扩大视野的参考，但需扩展 FPGA 接口后才能与之直接比较。OpenCV 的 `INTER_LINEAR` 图像是浮点模型的软件基准；随后仍需对 FPGA 的定点舍入、字节序和边界策略单独比对。

原始图像和生成结果目录已在 `.gitignore` 中排除。保留这些数据以便复现，但提交或共享前由数据持有人决定是否公开。

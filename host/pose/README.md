# 上位机姿态估计

`pose/` 负责从原始 UVC 图像估计棋盘格相对零位的相机姿态。它读取 `host/calibration/calibrate.py` 产生的 `calibration.json`，在运行时输出平移、相对旋转矩阵和 XYZ 欧拉角 JSON Lines。它不对视频帧做畸变矫正，也不通过 UART 下发参数。

在真实标定参数和相机姿态数据准备好之前，可先用 [`render_rotation_reference.py`](render_rotation_reference.py) 检查画面内旋转的逆向坐标约定和裁剪范围。该脚本默认自行生成 1280×720 合成棋盘格，因此不依赖相机或标定文件。

```powershell
.\.venv\Scripts\python.exe host\pose\render_rotation_reference.py `
  --out host\pose\output
```

默认生成 `0°、±10°、±20°` 的图像、四邻域有效区域掩码和 `rotation_reference.json`。使用现有图片时加 `--input path\to\image.png`；覆盖角度列表时使用 `--angles-deg 0 -10 10 -20 20`。输出到 `host/pose/output/` 的图片与 JSON 已加入忽略规则。

下一步可以在没有标定数据时检查平面倾斜产生的透视变化：

```powershell
.\.venv\Scripts\python.exe host\pose\render_homography_reference.py `
  --out host\pose\output
```

默认使用合成 1280×720 图像、`fx=fy=900 px`、图像中心主点、1000 mm 平面距离，对 X/Y 轴的 `0°、±10°、±20°` 倾斜生成透视参考图、四邻域有效掩码和 `homography_reference.json`。例如 `--fx`、`--fy`、`--cx`、`--cy`、`--plane-distance-mm` 可设置另一组合成参数；`--input` 可换成理想（未畸变）的平面参考图，`--translation-mm TX TY TZ` 可设置每个姿态的附加平移。

该脚本计算从理想零位输出像素到当前理想输入像素的单应矩阵，再执行逆向采样。参数只是用于开发坐标、透视和裁剪逻辑的合成值，不代表相机实测结果；此模型不含镜头畸变，也不能校正有景深场景的视差。真实标定完成后，再把标定内参和姿态日志接入同一映射链路。

## 姿态转换与候选定点系数

[`export_pose_homography.py`](export_pose_homography.py) 把 `track_pose.py` 的相对旋转、相对平移与零位棋盘平面组合成输出到输入的单应矩阵。没有实测标定文件时，直接生成 X/Y 轴 `0°、±10°、±20°` 的已知姿态，并比较浮点与候选定点坐标图：

```powershell
.\.venv\Scripts\python.exe host\pose\export_pose_homography.py `
  --analyze-maps --analyze-reciprocal `
  --out host\pose\output\pose_homography.jsonl
```

可用 `--fx`、`--fy`、`--plane-distance-mm` 和合成图像尺寸改变演示参数。等真实标定和零位文件生成后，改用姿态日志：

```powershell
.\.venv\Scripts\python.exe host\pose\export_pose_homography.py `
  --pose-log host\calibration\output\pose_log.jsonl `
  --calibration host\calibration\output\calibration.json `
  --reference host\calibration\output\reference_pose.json `
  --out host\pose\output\pose_homography.jsonl
```

输出逐行保留 `frame_index`、时间戳和有效标记。若姿态无效，导出记录也无效且不含变换系数，避免复用上一个姿态。有效记录包含浮点矩阵及候选 32 位系数：分子两行是有符号 Q16.16，分母一行是有符号 Q2.30，输出源坐标是现有采样链路使用的有符号 Q16.16。系数按最近整数取整，遇到正好半整数时取偶数；JSON 同时提供十进制、32 位补码十六进制及 Stage 8 参数模块的 288 位总线打包值。总线打包顺序不是 UART 字节序。

`--analyze-maps` 比较系数量化及输出坐标 Q16.16 取整后的全帧坐标和四邻域有效掩码。它尚未模拟 FPGA 乘加、除法器的位宽、舍入时序，也未定义 UART 包。实际硬件接口与流水线位宽仍需据此确定。平面单应矩阵只适用于棋盘平面；真实视频若包含不同深度的物体，镜头畸变和视差要另行处理。

`--analyze-reciprocal` 进一步使用整数乘加、1024 项倒数查找表和一次牛顿迭代，检查 Stage 8 的候选运算范围、坐标误差与有效掩码。完整格式和帧边界约定见 [`Stage 8 设计说明`](../../docs/plan/2026-10-24-stage8-angle-mapping.md)。该模型尚不代表 FPGA 实际时序或 DDR 吞吐率。

## 数据流

```text
标定原图 --calibrate.py--> calibration.json
零位原图 --capture_reference_pose.py--> reference_pose.json
UVC 实时帧 --track_pose.py--> pose estimates (JSONL)
```

标定参数必须对应运行时相机的分辨率、镜头和对焦状态。零位图应在相机与标定板固定、目标初始姿态确认后采集，并使用同一块 9×6 内角点棋盘格。跟踪过程要求棋盘格持续出现在画面中。

## 保存零位姿态

```powershell
.\.venv\Scripts\python.exe host\pose\capture_reference_pose.py `
  --calibration host\calibration\output\calibration.json `
  --image host\calibration\images\zero_pose.png `
  --out host\calibration\output\reference_pose.json `
  --display
```

工具检查图像尺寸与标定分辨率一致，检测棋盘格并使用 `solvePnP` 保存零位的 board-to-camera 旋转、平移及标定文件 SHA-256。

## 实时跟踪

默认打开 UVC 摄像头 0；按 `q` 退出预览：

```powershell
.\.venv\Scripts\python.exe host\pose\track_pose.py `
  --calibration host\calibration\output\calibration.json `
  --reference host\calibration\output\reference_pose.json `
  --source 0 --display `
  --output host\calibration\output\pose_log.jsonl
```

也可以用视频文件回放：

```powershell
.\.venv\Scripts\python.exe host\pose\track_pose.py `
  --calibration host\calibration\output\calibration.json `
  --reference host\calibration\output\reference_pose.json `
  --source host\pose\samples\pose_sweep.mp4
```

每帧输出包含 `valid`、时间戳、帧序号、相对旋转矩阵、相对平移和 `euler_xyz_deg`。无角点或姿态解算失败时输出带原因的无效记录，避免沿用旧角度。角度使用 `R_delta = R_current * R_reference^T`，并按 `Rz(yaw) * Ry(pitch) * Rx(roll)` 分解；最终 FPGA 的正负号仍须用已知方向的实物转动确认。

当前打印棋盘格对 180° 朝向存在对称歧义。若跟踪中姿态跳变，应在目标上加入固定的不对称标记或改用 ChArUco/ArUco。平面棋盘格姿态只能用于标定板平面或纯旋转近似；不能把单一平面变换解释成整个有景深场景的完整透视校正。UART 包格式待 FPGA 寄存器接口确定后再定义。

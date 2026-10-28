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

当前打印棋盘格对 180° 朝向存在对称歧义。若跟踪中姿态跳变，应在目标上加入固定的不对称标记或改用 ChArUco/ArUco。平面棋盘格姿态只能用于标定板平面或纯旋转近似；不能把单一平面变换解释成整个有景深场景的完整透视校正。Stage 8 当前 UART 协议为版本 `02`、65 字节，离线生成方式见下节。

## 从角度图片生成 UART 帧

[`encode_rotation_images_uart.py`](encode_rotation_images_uart.py) 会重新读取 `picture/Calibration/parallel angle/` 中以角度命名的棋盘格 PNG，使用当前 `calibration.json` 检测并去畸变角点，按文件名顺序解开棋盘格的 180° 方向歧义，再计算每张图相对第一张图的旋转矩阵。脚本把矩阵量化为 Stage 8 Q16.16/Q2.30 系数，检查数值范围，生成带 20 字节全零扩展区和 CRC-16/CCITT-FALSE 的 65 字节版本 `02` 请求帧并打印十六进制。它只打印数据，不会打开或发送到串口。

在 `Distortion-correction/` 目录运行：

```powershell
.\.venv\Scripts\python.exe host\pose\encode_rotation_images_uart.py
```

默认逐图打印整个角度序列。只看文件名为 `30.png` 的帧：

```powershell
.\.venv\Scripts\python.exe host\pose\encode_rotation_images_uart.py --only-angle 30
```

帧中的序号默认按排序后的图片从 1 递增；序号只是参数版本号，不代表角度。将 `UART_HEX` 后的 65 字节复制到串口工具，以 115200、8-N-1、十六进制发送。该离线角度图只用于逐帧检查参数编码，不表示运行时视频跟踪，也不补偿采集时额外的平移、缩放和透视变化。

## OBS 单帧测角并发送一次

[`measure_obs_rotation_send_uart.py`](measure_obs_rotation_send_uart.py) 固定使用 `picture/Calibration/00.png` 作为方向参考。它从 OBS 虚拟摄像机读取 5 张有效帧，对去畸变后的棋盘格中间行方向求平均，以模 180° 的相对角生成纯像平面旋转单应矩阵；然后通过 UART 发送**一次** 65 字节版本 `02` Stage 8 参数包、等待并验证 65 字节 ACK 后退出，不会持续更新角度。该流程不使用 `track_pose.py` 的 Euler yaw，因此不会把棋盘格 180° 对称分支直接当作旋转角发送。

在 `Distortion-correction/` 目录运行：

```powershell
.\.venv\Scripts\python.exe host\pose\measure_obs_rotation_send_uart.py
```

默认 OBS 设备索引为 2，串口为 COM7，串口配置为 115200、8-N-1；可用 `--source` 或 `--port` 覆盖。加 `--dry-run` 只测量并打印参数，不打开串口；加 `--save-frame path\to\frame.png` 保存所选输入帧。脚本将角度限制在相对 `00.png` 的 `[-90°, 90°)` 分支内；单张对称棋盘格图无法区分相差 180° 的真实姿态，因此此方法适用于相对参考图小于 90° 的像平面旋转。它不会补偿棋盘格平面外的平移、缩放或透视，也不能消除多深度场景视差。

## OBS 连续测角并实时发送

[`track_obs_rotation_continuous.py`](track_obs_rotation_continuous.py) 使用同一张固定 `00.png` 参考图，逐帧测量 OBS 虚拟摄像机中的棋盘格方向，并在同一次运行内对模 180° 角度做连续展开。每检测到一帧有效棋盘格，就发送一组递增序号的矩阵参数并等待对应 ACK，再处理下一帧。棋盘格暂时丢失时不发送旧参数，FPGA 保持最后一次已接受的矩阵；按 `Ctrl+C` 停止后脚本关闭串口，FPGA 仍保持最后一次矩阵。

```powershell
.\.venv\Scripts\python.exe host\pose\track_obs_rotation_continuous.py
```

默认 OBS 设备索引为 2、串口为 COM7，通信设置为 115200、8-N-1。可使用 `--source`、`--port` 和 `--sequence` 覆盖默认值。角度连续展开要求相邻成功检测之间的实际旋转小于 90°；启动时仍假设棋盘格相对 `00.png` 小于 90°。如果从任意大角度开始，或相机转得太快导致相邻采样跨过 90°，对称棋盘格本身无法确定正确分支，需要使用 ArUco/ChArUco 等方向标记。该脚本校正的是棋盘格平面内的旋转，不处理平移、倾斜透视或不同深度的视差。

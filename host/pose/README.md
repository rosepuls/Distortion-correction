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

[`track_obs_rotation_continuous.py`](track_obs_rotation_continuous.py) 使用同一张固定 `00.png` 参考图，启动时要求完整检测一次棋盘格以建立角点编号和初始方向；之后通过前后向光流跟踪角点，用 RANSAC 从仍可见的部分角点估计像平面旋转，并在同一次运行内对模 180° 角度做连续展开。只有至少 8 个跟踪点且 RANSAC 内点比例不低于 60% 时才发送递增序号的矩阵参数并等待对应 ACK。置信度不足时不发送参数，FPGA 保持最后一次已接受的矩阵；跟踪丢失后等待完整棋盘重新初始化。按 `Ctrl+C` 停止后脚本关闭串口，FPGA 仍保持最后一次矩阵。

该连续跟踪器仍只校正棋盘格所在像平面的旋转，不估计完整 3D 姿态，也不能消除不同深度物体的视差。对称棋盘格仍有 180° 方向歧义；从任意角度启动或发生严重跟踪丢失后，需要完整棋盘重新初始化，若需任意朝向可靠重锁，应增加不对称方向标记。

```powershell
.\.venv\Scripts\python.exe host\pose\track_obs_rotation_continuous.py
```

默认 OBS 设备索引为 2、串口为 COM7，通信设置为 115200、8-N-1。可使用 `--source`、`--port` 和 `--sequence` 覆盖默认值。角度连续展开要求相邻成功检测之间的实际旋转小于 90°；启动时仍假设棋盘格相对 `00.png` 小于 90°。如果从任意大角度开始，或相机转得太快导致相邻采样跨过 90°，对称棋盘格本身无法确定正确分支，需要使用 ArUco/ChArUco 等方向标记。该脚本校正的是棋盘格平面内的旋转，不处理平移、倾斜透视或不同深度的视差。

## 自动采集光照分类样本

[`capture_lighting_samples.py`](capture_lighting_samples.py) 从 OBS 虚拟摄像机读取原始 BGR 帧，复用 `lighting_profile.py` 的分类规则。连续 3 帧分类一致后开始采集；每类默认最多保存 15 张，并限制同一类别每秒最多保存 1 张。某类达到上限后会跳过该类，继续收集其他类别；六类都满后自动退出。默认显示带分类状态和样本计数的预览窗口，按 `q` 可提前结束。

在 `Distortion-correction/` 目录运行：

```powershell
.\.venv\Scripts\python.exe host\pose\capture_lighting_samples.py
```

默认读取 OBS 虚拟摄像机索引 2，要求输入为 1280×720。图像按 `0_bypass`、`1_night`、`2_night_strong`、`3_highlight`、`4_highlight_strong`、`5_mixed` 分目录保存在 `host/pose/output/lighting_samples/`；`manifest.jsonl` 记录图像路径、稳定类别和亮度统计。已存在的 `sample_*.png` 会计入每类上限，重新运行可接着补齐。可用 `--source` 指定其他摄像头索引或视频文件，`--output` 指定保存目录，`--no-preview` 关闭窗口。

## 生成并比较增强曲线候选

六条曲线的参数在 [`lighting_curve_parameters.json`](lighting_curve_parameters.json) 中独立配置。当前候选用 gamma 曲线提亮暗部，用 knee/shoulder 曲线压缩高光；`5:mixed` 组合两者。参数需结合新拍的带纹理场景继续调整。

2026-10-29 为便于首轮上板辨认，已加强 1–5 号候选：gamma 为 `0.68/0.45`，高光肩部参数为 `(knee=112,power=1.55)` 和 `(88,1.80)`，混合曲线为 `(gamma=0.65,knee=155,power=1.65)`。0 号仍为旁路。该组参数会明显改变中间调，当前用于快速确认链路，不代表最终画质参数。

对自动采集的样本生成 LUT、逐图指标和每类对照图：

```powershell
.\.venv\Scripts\python.exe host\pose\compare_lighting_curves.py
```

默认读取 `host/pose/output/lighting_samples/`，输出到 `host/pose/output/lighting_curve_comparison/`。每个类别生成一张对照图，列顺序为原图、0–5 号曲线；`metrics.csv` 记录平均亮度、暗部提亮量、高光保留比例及 RGB 平均变化；`lighting_luts.json` 保存实际 6×256 个表值。重拍时可用 `--input` 指向新目录，再运行同一命令。

## OBS 实时光照检测并发送 Stage 11 曲线

[`track_obs_adaptive_enhancement.py`](track_obs_adaptive_enhancement.py) 从原始 OBS 虚拟摄像机读取 1280×720 BGR 帧，复用 `lighting_profile.py` 的 0–5 号分类及连续 3 帧防抖。模式改变时使用 65 字节版本 `02` UART 请求发送曲线编号，并验证 FPGA 的完整 ACK、CRC 与负载回显。默认 COM7、OBS 设备索引 2；按 `Ctrl+C` 停止。运行前关闭其他占用 COM7 的串口脚本和串口助手；OBS 输入应为未经 FPGA 增强的原始画面。

只试图像增强时，显式指定单位矩阵模式（会替换板上现有角度矩阵）：

```powershell
.\.venv\Scripts\python.exe host\pose\track_obs_adaptive_enhancement.py --identity
```

同时进行角度矫正与图像增强时，不加 `--identity`。脚本先通过完整棋盘格锁定角点，再实时更新角度；跟踪暂时丢失时仍继续判断光照，如曲线变化则携带最后一次 ACK 确认的矩阵发送。在首次取得有效矩阵之前不发送曲线请求。

```powershell
.\.venv\Scripts\python.exe host\pose\track_obs_adaptive_enhancement.py
```

可用 `--source`、`--port`、`--stable-frames` 和 `--report-every` 调整输入与报告间隔。停止脚本后，FPGA 保持最后一次已接受的曲线和矩阵。当前曲线与分类阈值仍是候选参数；这条实时链路用于观察实际效果，不代表画质收益已经验收。

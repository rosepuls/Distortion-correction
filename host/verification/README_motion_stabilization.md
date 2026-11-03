# Stage13 防抖实板对比测量

从 `Distortion-correction` 目录运行。先关闭占用 OBS 虚拟摄像机、HDMI 采集卡或 COM7 的其他脚本；当前位流应使用 Stage13 UART v2 平移协议及与其匹配的 `.fic`。设备默认值统一从 [`device_config.json`](device_config.json) 读取；当前记录为 OBS Virtual Camera 索引 2、USB HDMI 采集卡索引 1、COM7/115200，目标画面为 1280×720。换 USB 插口后的识别步骤见[设备配置说明](README_devices.md)。当前位流支持每轴 ±24 px，因此脚本默认补偿上限也设为 ±24 px，无需额外参数。

固定机位静态场景，先运行关闭补偿的基线：

```powershell
.\.venv\Scripts\python.exe host\pose\verify_motion_stabilization.py --mode fixed --control off
```

再运行开启补偿的对照：

```powershell
.\.venv\Scripts\python.exe host\pose\verify_motion_stabilization.py --mode fixed --control on
```

可重复的平移扰动与连续视频分别改用 `--mode perturbation`、`--mode continuous`；两种控制状态仍分别运行。固定机位测试中镜头、焦距、曝光、场景和照明应保持一致；扰动和连续视频测试应尽量重放相同运动。前景运动物体可作为单独的干扰场景，观察全局光流置信度及残余位移变化。

启动后只预览，两路累计读帧数在画面上以黄色显示。按 **Space** 时先向 FPGA 发送零补偿配置并等待 ACK；`off` 模式关闭平移补偿，`on` 模式启用零初值。等待 0.5 秒后开始测量。运行所需时长后再次按 **Space** 结束；按 **q** 退出。只有测量时段写日志：每秒一条 `second` 记录，结束时一条 `summary` 记录。文件保存在 `host/verification/motion_stabilization/`，文件名含开始时间、场景模式和补偿状态。终端同步输出相同 JSON。可在同一程序内多次按 Space 开始新测量时段，各段以 `session` 区分。

记录内容包括：输入估计位移、发送补偿、输出残余位移、有效/无效估计及比例、UART ACK/NACK/其他错误数、最近 ACK 序号、采集设备帧间隔均值/P95/最大值、输出边界连通近黑候选占比、输入/输出特征轨迹方差，以及时长、帧数、分辨率、源设备和滤波参数。输入/输出光流分别在各自视频流中估计，因此输出残余位移是观测值，不是逐帧严格同步配对值。黑边占比是图像估计，场景本身紧贴边界的黑色物体也可能计入。固定场景方差依赖背景特征占多数；移动前景占据画面大部分时应单独报告该条件。

设备读帧数与帧间隔不能证明 FPGA 新处理帧率。`fpga_active_param_version` 记录为 `null`，因为现有 UART ACK 只证明参数被接受，不能直接读出活动参数组版本；`last_acked_sequence` 记录最后接受的请求序号。FPGA 输入、发布、处理、显示的新帧数需要额外的 Fabric Debugger 快照。可在测量期间向 JSONL 文件追加两次以上带时区时间戳的探针值，然后运行：

```powershell
.\.venv\Scripts\python.exe host\pose\verify_motion_stabilization.py --mode continuous --control on --probe-snapshots host\verification\motion_stabilization\probe_snapshots.jsonl
```

快照格式与 [实时旋转校正说明](README_live_rotation.md)中的四计数字段相同。脚本仅把开始时间位于本次测量时段内的窗口写入 `fpga_counter_window`；没有有效快照时为 `null`。两次快照应使用同一 `.sbit/.fic` 和同一观测窗口，建议间隔 30–60 秒。

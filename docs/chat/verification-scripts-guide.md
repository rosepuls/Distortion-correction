# 验证脚本功能与运行入口

本文汇总本项目图像验证、超分辨率预览、角度校正、防抖和灯光增强测试中使用的脚本。路径均相对于 `Distortion-correction` 工程根目录。

## 当前设备配置

共享设备文件：[`host/verification/device_config.json`](../../host/verification/device_config.json)

当前配置记录：

| 设备 | 配置值 | 备注 |
|---|---:|---|
| OBS Virtual Camera DirectShow 索引 | 2 | 已扫描确认 OBS 运行时对应索引 2 |
| HDMI 采集卡 DirectShow 索引 | 1 | 已确认采集卡画面对应索引 1 |
| USB-UART | COM7 | 配置文件仍是 COM7；最近一次端口扫描只发现 COM8、COM9，使用 UART 前需确认转串口设备并更新 |
| 默认视频请求尺寸 | 1280×720 | 这是软件请求尺寸；采集卡实际返回尺寸另行读取 |

从 PowerShell 在工程根目录运行脚本。多数 Python 脚本使用项目虚拟环境：

```powershell
Set-Location 'C:\Study\IC_Study\Project\FPGA\Contest\Pango_Micro_FPGA\Distortion-correction'
.\.venv\Scripts\python.exe <脚本路径> <参数>
```

若视频设备换 USB 口或 OBS 虚拟摄像头启停后索引变化，先扫描并预览：

```powershell
.\.venv\Scripts\python.exe host\verification\configure_devices.py --scan --preview
```

修改共享索引示例：

```powershell
.\.venv\Scripts\python.exe host\verification\configure_devices.py --set-obs 2 --set-hdmi 1
```

确认 USB-UART 端口后，可在同一命令中追加 `--set-com COM8` 或实际端口。配置工具会列出可读的视频索引和当前串口；不能只凭分辨率判断视频源身份，应检查预览画面。

## 图像与分辨率验证

### OBS 与 FPGA HDMI 并排预览

脚本：[`host/verification/preview_obs_hdmi.py`](../../host/verification/preview_obs_hdmi.py)

左侧读取 OBS 虚拟摄像头，右侧读取 HDMI 采集卡，画面上标记两路实际交付给 OpenCV 的帧尺寸。`q` 或 `Esc` 退出。脚本不发 UART。

普通 720p 预览：

```powershell
.\.venv\Scripts\python.exe host\verification\preview_obs_hdmi.py
```

Stage12 目标输出 1080p 时，可向 HDMI 采集卡单独请求 1920×1080，OBS 仍请求默认 1280×720：

```powershell
.\.venv\Scripts\python.exe host\verification\preview_obs_hdmi.py --hdmi-width 1920 --hdmi-height 1080
```

脚本请求及读到的帧尺寸不等同于 HDMI 线上原始信号时序；采集卡可能在内部缩放。要证明 FPGA 输出时序为 1920×1080@60 Hz，应查看直连显示器的输入信号信息，或采集卡工具报告的 HDMI 输入格式。

### HDMI 采集卡单路预览

脚本：[`host/pose/preview_hdmi_usb_capture.py`](../../host/pose/preview_hdmi_usb_capture.py)

只打开 HDMI 采集卡，不依赖 OBS 虚拟摄像头。默认设备索引和请求尺寸来自共享配置；可用 `--source`、`--width`、`--height` 覆盖。`q` 或 `Esc` 退出。

```powershell
.\.venv\Scripts\python.exe host\pose\preview_hdmi_usb_capture.py
.\.venv\Scripts\python.exe host\pose\preview_hdmi_usb_capture.py --source 1 --width 1920 --height 1080
```

第二条命令请求采集卡返回 1080p 帧，不足以独立证明 FPGA HDMI 输入时序为 1080p。

### 单帧几何、黑边与清晰度测量

脚本：[`host/verification/measure_hdmi_sfr.py`](../../host/verification/measure_hdmi_sfr.py)

关闭其他占用采集卡的预览后运行。每次采一帧，测量棋盘网格直线度、边界近黑区域、斜边 SFR/MTF50；保存未标注 FPGA 输出 PNG、标注图、CSV 和 JSONL 记录。若采集图没有合格斜边，SFR 会标为不可用。该脚本不能测量 HDMI 原始时序。

```powershell
.\.venv\Scripts\python.exe host\verification\measure_hdmi_sfr.py --image-id 0 --width 1280 --height 720
```

更换 OBS 测试图后将 `--image-id` 改为对应编号（当前验证图为 0–7）。默认结果目录：`host/verification/capture_results/`。每次运行的 `_fpga.png` 是采集帧原图，可用于报告；`measurements.jsonl` 追加指标。

## 角度校正

### 手动角度参考的实板评估

脚本：[`host/pose/verify_live_rotation.py`](../../host/pose/verify_live_rotation.py)

同时读取 OBS 和 FPGA HDMI，使用棋盘估计输入角度、通过 UART 下发矩阵，并测量输出残余倾角、预测有效面积和 ACK 状态；可选关联 Fabric Debugger 计数快照。零位与每次测量由用户操作，启动时仅预览。当前源代码支持终端操作流程：转台 0° 时输入 `0` 后回车，稳定后输入 `z` 设置输出基线；每到一个角度输入实际角度后回车，再输入 `m` 回车测量一次；输入 `q` 退出。预览窗口也保留快捷键。日志仅在触发测量时写入。

```powershell
.\.venv\Scripts\python.exe host\pose\verify_live_rotation.py
```

输出目录：`host/verification/live_rotation/`，包括 `measurements.jsonl` 及测量帧。脚本使用 UART，运行前需先把 `device_config.json` 中的 COM 端口改成实际 USB-UART 端口。

### OBS 单帧估角并下发矩阵

脚本：[`host/pose/measure_obs_rotation_send_uart.py`](../../host/pose/measure_obs_rotation_send_uart.py)

从 OBS 取棋盘帧，对若干有效帧估计旋转并生成单应矩阵，通过 UART 发送一次并等待匹配 ACK；可用 `--dry-run` 只生成/显示参数、不打开 UART，`--save-frame` 保存输入帧。

```powershell
.\.venv\Scripts\python.exe host\pose\measure_obs_rotation_send_uart.py --dry-run
```

正式发送前确认位流协议、标定文件及 UART 端口匹配。

### OBS 连续角度跟踪

脚本：[`host/pose/track_obs_rotation_continuous.py`](../../host/pose/track_obs_rotation_continuous.py)

连续跟踪 OBS 棋盘特征；全棋盘初始化后使用局部特征更新旋转估计，置信度达标时通过 UART 发送矩阵并校验 ACK。需要匹配的 FPGA UART 协议、有效棋盘和串口。

```powershell
.\.venv\Scripts\python.exe host\pose\track_obs_rotation_continuous.py
```

## 运动防抖

### 实板开关补偿对照测量

脚本：[`host/pose/verify_motion_stabilization.py`](../../host/pose/verify_motion_stabilization.py)

同时读取 OBS 输入和 FPGA HDMI 输出，使用特征跟踪估计位移；统计输入位移、补偿值、输出残余位移、轨迹方差、无效估计、UART ACK/NACK、设备读帧间隔及近黑边候选。支持 `fixed`、`perturbation`、`continuous` 场景以及 `on`、`off` 控制。启动后先预览，按空格开始，再按空格结束；`q` 退出。只在测量区间记录日志。默认每轴补偿范围为 ±24 px。

固定场景关闭补偿：

```powershell
.\.venv\Scripts\python.exe host\pose\verify_motion_stabilization.py --mode fixed --control off
```

固定场景开启补偿：

```powershell
.\.venv\Scripts\python.exe host\pose\verify_motion_stabilization.py --mode fixed --control on
```

另两种模式将 `fixed` 改为 `perturbation` 或 `continuous`。结果默认保存到 `host/verification/motion_stabilization/`。脚本需要匹配的 Stage13 UART v2 位流和已确认的 COM 口。电脑侧视频读帧数不代表 FPGA 新处理帧数；后者需用匹配 `.sbit/.fic` 的 Fabric Debugger 快照。

### 在线防抖参数跟踪发送

脚本：[`host/pose/stage13_motion_stabilization.py`](../../host/pose/stage13_motion_stabilization.py)

从 OBS 估计画面运动，按置信度、死区、低通和限幅生成平移补偿参数并通过 UART 发送；默认最大补偿 ±24 px。`--dry-run` 不开串口，`--display` 显示跟踪预览。此脚本属于在线控制入口，不等于离线 A/B 评估。

```powershell
.\.venv\Scripts\python.exe host\pose\stage13_motion_stabilization.py --dry-run --display
```

## 灯光增强曲线

### 单次 UART 曲线切换

Stage11 脚本：[`fpga/project/stage11_720p60hz_adaptive_image_enhancement_test/sim/Run-UartEnhancementProfile.ps1`](../../fpga/project/stage11_720p60hz_adaptive_image_enhancement_test/sim/Run-UartEnhancementProfile.ps1)

每次执行发送一个 profile 更新包并等待 ACK。相机和画面可保持不动，依次比较 ProfileId 0–5；每成功收到 ACK 后递增 Sequence 和 ProfileId。显式 `-Com` 会覆盖共享配置。

```powershell
& '.\fpga\project\stage11_720p60hz_adaptive_image_enhancement_test\sim\Run-UartEnhancementProfile.ps1' -Com COM8 -Sequence 103 -ProfileId 0
```

示例中的 COM8 仅在确认它是 USB-UART 适配器后使用。串口当前枚举结果与配置文件中的 COM7 不符；先核实设备，勿同时运行其他占用该串口的程序。

### OBS 连续自适应曲线跟踪

脚本：[`host/pose/track_obs_adaptive_enhancement.py`](../../host/pose/track_obs_adaptive_enhancement.py)

分析 OBS 视频亮度并持续选择/更新 Stage11 灯光增强 profile，通过 UART 下发；这是自动跟踪控制，不是手动逐档 A/B 工具。运行前确认串口协议和 COM 口。

```powershell
.\.venv\Scripts\python.exe host\pose\track_obs_adaptive_enhancement.py
```

### 增强前后成对采图

脚本：[`host/verification/capture_enhancement_pair.py`](../../host/verification/capture_enhancement_pair.py)

用于采集增强设置对照图像。具体参数请先查看脚本帮助，按帮助指定 OBS/HDMI 源、profile 和输出目录：

```powershell
.\.venv\Scripts\python.exe host\verification\capture_enhancement_pair.py --help
```

## 配置与结果文件

| 文件 | 用途 |
|---|---|
| [`host/verification/device_config.py`](../../host/verification/device_config.py) | 读取并校验共享设备配置 |
| [`host/verification/device_config.json`](../../host/verification/device_config.json) | OBS、HDMI、UART 和默认分辨率 |
| [`host/verification/README_devices.md`](../../host/verification/README_devices.md) | 设备扫描、索引配置和共享设备说明 |
| [`host/verification/README_live_rotation.md`](../../host/verification/README_live_rotation.md) | 角度校正评估流程和日志字段 |
| [`host/verification/README_motion_stabilization.md`](../../host/verification/README_motion_stabilization.md) | 防抖实板评估流程和指标限制 |

角度测量和防抖脚本同时占用 OBS、HDMI 与 UART；运行前关闭其他占用相同设备的预览或控制程序。测量日志与视频截图均记录在各脚本输出目录。

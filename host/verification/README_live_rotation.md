# 实时旋转校正验证

在 `Distortion-correction` 目录运行：

```powershell
.\.venv\Scripts\python.exe host\pose\verify_live_rotation.py
```

设备默认值统一从 [`device_config.json`](device_config.json) 读取；当前记录为 OBS Virtual Camera DirectShow 索引 2、HDMI USB 采集卡索引 1、COM7/115200。换 USB 插口后的识别步骤见[设备配置说明](README_devices.md)。两路应均为 1280×720。关闭占用这两个视频设备或 COM7 的预览、跟踪脚本。FPGA 应烧录与当前 UART 矩阵协议和标定 Brown K3 参数匹配的位流。

固定镜头、焦距、曝光、棋盘和光照。启动后仅预览视频，**不会测量、下发 UART 或写测量日志**。角度和操作在启动脚本的终端中输入，视频预览继续刷新。先把转台放在 0°，输入 `0` 回车设置角度；等 FPGA 输出画面稳定且棋盘完整可见后输入 `z` 回车设置输出方向零位。之后每到一个稳定位置，输入实际有符号角度（例如 `-12.5`）回车，再输入 `m` 回车测量一次。脚本才会从 OBS 图像估计角度、发送一次矩阵、等待默认 0.5 秒、采集 FPGA 输出并记录一次结果。可输入多个正角、负角及最后回到 0°。输入 `q` 回车退出。预览窗口也保留 `z`、空格、`q` 快捷键。

界面用黄色显示 OBS 和采集卡累计读帧数、实际角度及最近一次测量结果。只有按 `Space` 成功开始测量时，终端和 `host/verification/live_rotation/measurements.jsonl` 才追加一条结果；等待期间不写日志。每条测量同时在 `host/verification/live_rotation/frames/` 保存两张未标注的 PNG：`*_obs.png` 是按空格时用于输入角度估计的 OBS 帧，`*_hdmi.png` 是 UART 应答及稳定等待后用于输出倾角估计的采集卡帧。日志字段 `obs_input_png`、`hdmi_output_png` 给出完整路径；若某张图无法保存，路径为 `null`，原因写在 `image_save_errors`。输出残余倾角是采集卡画面棋盘方向相对按 `z` 保存方向的差值，按 180° 棋盘对称性折算。预测有效面积按已标定 Brown 模型及严格 2×2 边界计算，属于几何预测值。输入棋盘检测失败时不发 UART 包，也不写测量记录；UART 错误会作为该次测量的结果记录。

视频设备读帧数不是 FPGA 新处理帧数。FPGA 输入、发布、处理、显示新帧需要从同一位流对应的 Fabric Debugger FIC 获取。可将带时间戳的快照逐行追加到 JSONL，并把路径传给脚本：

```powershell
.\.venv\Scripts\python.exe host\pose\verify_live_rotation.py --probe-snapshots host\verification\live_rotation\probe_snapshots.jsonl
```

每行格式如下，十六进制计数保留为字符串；时间戳需含时区：

```json
{"time":"2026-11-02T10:00:00+08:00","raw_input_vsync_count":"0x061e","input_published_count":"0x0000061d","copied_count":"0x0000061c","display_take_count":"0x0000061b"}
{"time":"2026-11-02T10:00:40+08:00","raw_input_vsync_count":"0x0f47","input_published_count":"0x00000f46","copied_count":"0x00000f45","display_take_count":"0x00000f45"}
```

脚本用相邻两次快照的时间差和计数差生成 `fpga_counter_window`，其中包含同一观测窗口内四级新帧数和窗口时长，不显示帧率。16 位输入 VSYNC 按回绕计算；32 位计数若重置或饱和则拒绝计算。没有快照时该字段为 `null`。Fabric Debugger 的通道对应关系见当前工程的 `README_JTAG.md`；快照必须来自与烧录 `.sbit` 匹配的 `.fic`。

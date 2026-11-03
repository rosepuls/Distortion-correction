# 验证设备统一配置

各验收脚本共用 [`device_config.json`](device_config.json)：OBS 虚拟相机 DirectShow 索引、FPGA HDMI 采集卡 DirectShow 索引、UART COM 号和画面尺寸。实际索引以该文件当前内容为准。采集卡换 USB 插口后，**视频索引可能改变**；物理 USB 插口不能预先推算 OpenCV 的索引。

换口并接好线、启动 OBS 虚拟相机后，先关闭其他占用视频设备和 COM7 的脚本，在 `Distortion-correction` 目录运行：

```powershell
.\.venv\Scripts\python.exe host\verification\configure_devices.py --scan --preview
```

每个可打开的视频索引会显示一幅带黄色编号的预览。确认哪个是 OBS 原始画面、哪个是 FPGA HDMI 输出画面。如果与 `device_config.json` 一致，无需修改。若换口后成为 OBS `2`、HDMI `3`，运行：

```powershell
.\.venv\Scripts\python.exe host\verification\configure_devices.py --set-obs 2 --set-hdmi 3
```

若 COM 号也改变，再加 `--set-com COM8`。配置工具会同时列出当前串口。改变一次配置后，`measure_hdmi_sfr.py`、`preview_obs_hdmi.py`、`verify_live_rotation.py`、`verify_motion_stabilization.py`、`preview_hdmi_usb_capture.py`、实时角度/增强/防抖跟踪脚本，以及 Stage11 `Run-UartEnhancementProfile.ps1` 的默认设备会同步更新。命令行显式写出的 `--source`、`--obs-source`、`--hdmi-source`、`--port` 或 `-Com` 会覆盖共享配置；为使用更新后的默认值，Stage11 命令请省略 `-Com COM7`。

超分辨率画面对照预览使用 `python host/verification/preview_obs_hdmi.py --hdmi-width 1920 --hdmi-height 1080`。窗口左侧为 OBS 虚拟相机（默认请求 1280×720），右侧为 FPGA HDMI 采集卡（此命令请求 1920×1080）；黄色文字显示每一路实际读取到的帧尺寸，而不是 HDMI 线的原始时序。窗口缩放不改变标签中的分辨率。按 `q` 或 `Esc` 退出。此预览不发送 UART 指令。

这些程序并非同时运行的四条视频管线。`measure_hdmi_sfr.py` 只读取 HDMI 采集卡，图像由 OBS 经 FPGA 输入；Stage11 PowerShell 脚本只通过 UART 切换曲线；两个双路评估脚本同时读取 OBS 虚拟相机与 HDMI 采集卡并占用 UART。运行其中一个时，关闭其他会争用相同设备的脚本。

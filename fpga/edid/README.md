# MS7200 720p60 EDID

`720p60.hex` 是写入 MS7200 的 256 字节 HDMI 接收端 EDID。基础块的首选详细时序为 1280×720、1650×750、74.25 MHz；CTA 扩展只声明原生 VIC 4（720p60），保留最小 HDMI 厂商数据块以便电脑按 HDMI 设备识别。两块各自的校验和均为 0。

厂商 `ms7200_ctl.v` 原来的 EDID 首选时序为 3840×2160，并在 CTA 扩展中列出 1080p。它的显示器名为 `U28H75x`，与 Windows 截图一致。阶段 1 的顶层只转发输入像素时钟和视频数据，修改顶层时序常量不会改变电脑发出的活动信号；必须修改 MS7200 向电脑提供的 EDID。

`../project/Set-Stage1Edid.ps1` 把该 EDID 写入本地生成工程的 `source/ms7200_ctl.v` 中 `0D00` 至 `0DFF` 的寄存器写入表，并核对字节数、校验和及表结构。`New-Stage1Project.ps1` 在生成工程时自动调用它。已存在的本地工程可单独运行：

```powershell
powershell -NoProfile -File .\fpga\project\Set-Stage1Edid.ps1
```

重新综合并下载位流后，拔插电脑到 FPGA 的 HDMI 线或重启视频源，让显卡重新读取 EDID。随后在 Windows“高级显示器设置”中核对**活动信号模式**为 1280×720、60 Hz。EDID 只声明期望的视频模式；若电脑手动强制输出不在 EDID 中的格式，FPGA 直通链路不会替它缩放。

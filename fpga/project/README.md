# PDS 工程

`New-Stage1Project.ps1` 从本机厂商例程生成 HDMI 直通工作工程。`stage1_hdmi_loop/` 是可重新生成的本地目录，不提交厂商源码和 IP。

阶段 2 以 PG2L200H 的 `4_10_timing/4_10_HDMI_IN_DDR3_HDMI_OUT` 为基线，在阶段 1 硬件验收后建立独立工作工程；不要复用阶段 1 的 PLL 或直接套用 1080p 时序。阶段 2 接收端也需要沿用 `fpga/edid/720p60.hex`，否则电脑可能重新选择 1080p 活动信号。

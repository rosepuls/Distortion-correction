# 盘古200Pro+ 上板记录模板

按以下顺序测试，并记录 bitstream 提交、PDS 报告、输入分辨率、显示器 OSD、`ddr_init_done`、HDMI 初始化状态、underflow/overflow 和持续运行时长：

1. 27 MHz/125 MHz、PLL 锁定、复位和 LED；
2. 电脑 HDMI 输入到 HDMI 输出直通；
3. DDR3 初始化和官方 BIST；
4. HDMI → DDR3 → HDMI 帧缓存；
5. 零畸变参数整链；
6. 标定参数和连续视频。

若电脑输出 720p60 而算法仍按 30 fps 处理，必须明确记录丢帧/采样策略；不得将非标准像素时钟假定为显示器可接受模式。

# PG2L200H 实时视频链路

当前物理顶层是 `rtl/board/pg2l200h/pg2l200h_board_top.sv`，目标器件为盘古 200Pro+ 的 `PG2L200H-6FBB676`。它使用 27 MHz 板载时钟、125 MHz DDR3 差分参考时钟、MS7200/MS7210 共享 I2C 和 `ddr3_test` Logos2 DDR3 IP。

处理链为：HDMI RX RGB888 → DDR3 输入帧 → `distortion_frame_processor` 随机读与双线性插值 → DDR3 输出帧 → HDMI TX RGB888。轻量视觉模块继续保持独立可复用；在确认要显示校正 RGB、二值边缘或叠加结果前，不把它们强行串入物理视频输出。

720p60 上板基线的 HDMI 像素时钟是 74.25 MHz。`video_pll/pll.idf` 和 `pll.v` 使用 27 MHz 输入和 ÷14 输出配置；首次 PDS 打开工程时必须在 IP Compiler 中重新生成并确认，不能拿仿真 stub 代替实际 PLL 或 DDR3 PHY。

上板工程入口、管脚、时钟及逐步验证顺序见：

- `boards/pg2l200h/README.md`
- `docs/board/pg2l200h_clock_plan.md`
- `docs/board/pg2l200h_bringup.md`

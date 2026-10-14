# PG2L200H PDS 实现交接

打开 `boards/pg2l200h/pds/pg2l200h_rtl_synth/pg2l200h_rtl_synth.pds`，或执行同目录 `impl.tcl`。目标必须显示为 `Logos2 / PG2L200H / -6 / FBB676`，顶层必须为 `pg2l200h_board_top`。

首次实现前，在 IP Generator 中重新生成：

- `ip/pango/pg2l200h/video_pll/`：27 MHz 输入到 74.25 MHz 输出；
- `ip/pango/pg2l200h/cfg_pll/`：HDMI 配置时钟；
- `ip/pango/pg2l200h/ddr3/`：使用官方 200Pro+ x32 DDR3 参数。

先执行编译、综合、映射、布局布线和时序报告；只有所有时钟、CDC 和 DDR PHY 报告可追溯后才生成 bitstream。

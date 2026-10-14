# 盘古200Pro+ 视频与 DDR 引脚基线

引脚约束以 `boards/pg2l200h/constraints/pg2l200h_board_top.fdc` 中的官方 200Pro+ HDMI+DDR3 示例为唯一真值来源。

| 信号 | 引脚 |
| --- | --- |
| 27 MHz 系统时钟 `sys_clk` | D18 |
| DDR 125 MHz `clk_p/clk_n` | N3 / N2 |
| 复位 `rst_in` | C22 |
| HDMI RX 像素时钟 `pixclk_in` | K21 |
| HDMI TX 像素时钟 `pix_clk` | T24 |
| HDMI 共享 I²C `hd_scl/hd_sda` | K22 / K23 |

不得复用旧板的 FDC、DDR 管脚、IO 电平或 PLL/PHY 派生时钟约束。

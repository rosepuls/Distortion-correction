# 200Pro+ / PG2L200H 板卡层

物理顶层为 `pg2l200h_board_top`。它以 27 MHz 系统时钟、125 MHz DDR 差分参考时钟、共享 HDMI I²C、MS7200/MS7210 并行 RGB 和 x32 DDR3 为板级边界；算法 RTL 不直接依赖本目录。

首轮上板顺序为：PLL/复位、HDMI 直通、DDR 初始化、HDMI-DDR-HDMI、零畸变整链。
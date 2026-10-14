# PG2L200H 时钟与复位规划

- `sys_clk`：板载 27 MHz，PDS 约束为 37 ns；
- `clk_p/clk_n`：专用 125 MHz DDR 差分参考时钟，PDS 约束为 8 ns；
- `pixclk_in`：由 MS7200 输出，按电脑 HDMI 实际输入模式约束；
- `pix_clk`：由 Logos2 视频 PLL 输出。项目 720p60 TX 目标为 74.25 MHz，必须在 PDS 中重新生成并记录实际参数；
- `core_clk`：由 `ddr3_test` 输出；
- `cfg_clk`：由独立 `cfg_pll` 输出，专用于 MS7200/MS7210 配置。

复位只能异步断言、各时钟域同步释放。跨域控制继续使用同步器或握手；像素与帧数据必须经 DDR 帧缓存、FIFO 或官方双口 RAM。旧板的 false path 和时序报告不可迁移。

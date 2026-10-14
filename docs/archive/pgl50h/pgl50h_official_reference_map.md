# PGL50H 官方资料映射

## 已核对的参考文件

| 目的 | 官方文件 | 结论 |
| --- | --- | --- |
| HDMI RX/TX 端口 | `board_reference/mes50hp/06_hdmi_loop/src/hdmi_loop.v` | MS7200 输入为 `pixclk_in/vs_in/hs_in/de_in/r_in/g_in/b_in`；MS7210 输出为 `pixclk_out/vs_out/hs_out/de_out/r_out/g_out/b_out`。 |
| HDMI 初始化 | `board_reference/mes50hp/06_hdmi_loop/src/ms72xx_ctl.v` | MS7200 和 MS7210 分别使用 `iic_scl/iic_sda` 与 `iic_tx_scl/iic_tx_sda`。 |
| DDR3 PHY | `board_reference/mes50hp/10_HDMI_DDR3_OV5640_test/source/rtl/DDR3_50H/DDR3_50H.v` | 50 MHz `ref_clk`，32-bit DDR3 DQ，256-bit AXI 读写数据通道。 |
| DDR3 写缓存 | `board_reference/mes50hp/10_HDMI_DDR3_OV5640_test/source/rtl/wr_buf.v` | 支持 `PIX_WIDTH=24`，RGB888 以 `{r,g,b}` 写入。 |
| DDR3 顺序显示读取 | `board_reference/mes50hp/10_HDMI_DDR3_OV5640_test/source/rtl/fram_buf.v` | 仅适合按显示时序连续读取；不能供畸变算法随机取样。 |
| HDMI 管脚约束 | `board_reference/mes50hp/06_hdmi_loop/src/hdmi_loop.fdc` | 包含 `sys_clk`、HDMI RGB/同步/I2C 与输出口的实际管脚、电平属性。 |
| DDR3 管脚和时序 | `board_reference/mes50hp/10_HDMI_DDR3_OV5640_test/hdmi_ddr_ov5640_top.fdc` | 包含 DDR3 HSTL15/HSTL15D 属性、DDR PHY 位置与生成时钟约束。 |

## 新物理顶层端口

新模块 `pgl50h_board_top` 只拥有物理端口：`sys_clk`、两组 HDMI I2C、MS7200 RGB888 输入、MS7210 RGB888 输出、`mem_*` DDR3 端口，以及 `hdmi_int_led`、`ddr_init_done`、`heart_beat_led` 状态输出。

现有 `mes50hp_top` 的 `cfg_*`、`frame_start/frame_busy/frame_done` 和 `mem_req_*/mem_rsp_*` 都是内部连线，不能再成为 PDS 顶层 IO。

# MES50HP 导入的厂商参考 RTL

本目录中的文件是为构建 `pgl50h_board_top` 从官方例程机械复制的来源文件；不得在 `board_reference` 中直接编辑对应文件。

| 当前目录 | 官方来源 | 作用 |
| --- | --- | --- |
| `hdmi/` | `06_hdmi_loop/src/` | `iic_dri`、`ms7200_ctl`、`ms7210_ctl` 和 `ms72xx_ctl`；完成 MS7200/MS7210 初始化。 |
| `ddr/wr_buf.v` 和 `ddr/wr_fram_buf/` | `10_HDMI_DDR3_OV5640_test/source/rtl/` | 24-bit RGB888 输入帧的行缓存和 DDR3 写请求。 |
| `ddr/wr_cmd_trans.v`、`ddr/wr_ctrl.v`、`ddr/rd_ctrl.v`、`ddr/wr_rd_ctrl_top.v` | `10_HDMI_DDR3_OV5640_test/source/rtl/` | 官方 DDR3 AXI 写/读命令转换和仲裁。 |
| `ddr/rd_fram_buf/` | `10_HDMI_DDR3_OV5640_test/source/rtl/` | DDR 时钟到 HDMI 像素时钟的 256-bit/32-bit 双口缓存。 |
| `video/sync_vg.v` | `10_HDMI_DDR3_OV5640_test/source/rtl/` | 官方 1280×720 输出时序发生器。 |

DDR3 控制器/PHY 位于 `ip/pango/DDR3_50H/`，视频 PLL 位于 `ip/pango/mes50hp_video_pll/`。两者来自 PDS 2022.1 生成结果，只能用于接口比对与 RTL/XSIM 结构验证；在当前 PDS 版本进行实板烧录前必须重新生成 IP 和更新其约束。

`rd_buf.v` 与 `fram_buf.v` 没有被直接导入。项目使用自有随机输入读取器和固定输出帧读取器，但复用官方 `rd_fram_buf` 完成输出侧跨时钟缓存。

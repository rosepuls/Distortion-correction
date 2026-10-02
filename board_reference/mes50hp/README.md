# MES50HP 官方例程参考副本

本目录是从用户提供的盘古 50K 官方资料中原样解压的只读参考，不作为当前项目的 PDS 工程直接打开或修改。

| 目录 | 来源 | 本项目用途 |
| --- | --- | --- |
| `06_hdmi_loop` | `2_Demo/06_hdmi_loop.rar` | MS7200 输入、MS7210 输出、HDMI I2C 初始化和 HDMI `.fdc` |
| `07_ddr3_test` | `2_Demo/07_ddr3_test.rar` | 独立 DDR3 IP、PHY 与校准参考 |
| `10_HDMI_DDR3_OV5640_test` | `2_Demo/10_HDMI_DDR3_OV5640_test.rar` | DDR3 AXI 路径、24 位 `wr_buf` 写通道、MS7210 输出和完整 DDR `.fdc` |

`10_HDMI_DDR3_OV5640_test` 的视频输入是 OV5640，不是 HDMI RX。新板级顶层必须使用 `06_hdmi_loop` 的 `pixclk_in/vs_in/hs_in/de_in/r_in/g_in/b_in` 作为 MS7200 输入，且不得继承 OV5640/CMOS 顶层端口。

官方例程标注为 PDS 2022.1。DDR3 和 PLL 生成文件在实际烧录前须按当前 PDS 版本重新生成。

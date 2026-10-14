# 200Pro+ / PG2L200H 厂商参考 RTL

本目录仅保存从官方 `4_10_HDMI_IN_DDR3_HDMI_OUT` 例程导入的 Logos2 HDMI、DDR 控制和 DRM 参考文件。

- `hdmi/`：MS7200/MS7210 的共享 I²C 初始化；
- `ddr/`：官方 256-bit AXI 帧缓存读写控制和 Logos2 双口缓存；
- `memory/`：项目 Tile Cache 的 Logos2 DRM 封装；
- `video/`：官方视频时序发生器参考。

生成 IP 位于 `ip/pango/pg2l200h/`；不得与旧 Logos 系列的 `ipml_*` 或 `ipsxb_*` IP 混用。
`ms72xx_ctl.v` 去除了对 ANSI 输出端口 `init_over_rx` 的重复 `wire` 声明；这不改变硬件连接，只是使该官方 Verilog 源可被 Vivado/XSim 与 PDS 同时解析。
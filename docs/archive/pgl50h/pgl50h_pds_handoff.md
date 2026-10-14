# PGL50H HDMI + DDR3 板级工程 PDS 操作清单

## 目标

在现有 `boards/pgl50h/pds/pgl50h_rtl_synth/pgl50h_rtl_synth.pds` 中将算法验证顶层升级为 MES50HP 实物顶层。当前工程的输入帧采用 RGBX8888、Tile Cache 随机读，目标为 1280×720@30。最终顶层必须是：

```text
pgl50h_board_top
```

文件位置：`rtl/board/pgl50h/pgl50h_board_top.sv`。

## 1. 保留现有算法源文件

保留当前工程中的以下文件：

```text
rtl/algorithm/distortion/coordinate_gen.sv
rtl/algorithm/distortion/normalize.sv
rtl/algorithm/distortion/coordinate_split.sv
rtl/algorithm/distortion/distortion_core.sv
rtl/algorithm/distortion/distortion_core_optimized.sv
rtl/algorithm/interpolation/bilinear_interp.sv
rtl/platform/common/memory/pixel_fetch_engine.sv
rtl/platform/common/memory/pixel_tile_cache.sv
rtl/platform/common/memory/ddr_burst_reader.sv
rtl/platform/common/memory/cached_pixel_fetch_engine.sv
rtl/algorithm/distortion/distortion_image_pipeline.sv
rtl/board/pgl50h/clock_reset.sv
rtl/board/pgl50h/mes50hp_top.sv
```

`distortion_core.sv` 仍是参数化 generate 分支的编译依赖，首轮 PDS 综合不要删除。

## 2. 加入新的板级 RTL

将以下文件加入 Design Source：

```text
rtl/board/pgl50h/board_video_control.sv
rtl/board/pgl50h/ddr3_rgbx_cache_adapter.sv
rtl/board/pgl50h/algorithm_frame_writer.sv
rtl/board/pgl50h/ddr3_frame_reader.sv
rtl/board/pgl50h/video_mode_720p30.sv
rtl/board/pgl50h/pgl50h_board_top.sv
```

## 3. 加入官方 HDMI、DDR 调度和视频 RTL

将以下厂商参考 RTL 加入 Design Source：

```text
rtl/vendor/pgl50h/hdmi/iic_dri.v
rtl/vendor/pgl50h/hdmi/ms7200_ctl.v
rtl/vendor/pgl50h/hdmi/ms7210_ctl.v
rtl/vendor/pgl50h/hdmi/ms72xx_ctl.v
rtl/vendor/pgl50h/ddr/wr_buf.v
rtl/vendor/pgl50h/ddr/wr_cmd_trans.v
rtl/vendor/pgl50h/ddr/wr_ctrl.v
rtl/vendor/pgl50h/ddr/rd_ctrl.v
rtl/vendor/pgl50h/ddr/wr_rd_ctrl_top.v
```

不要加入 `sim/models/pgl50h_board_vendor_stubs.sv`。它只用于 XSIM 结构测试，会与真实厂商模块重名。

## 4. 导入四个官方 IP

在 PDS 的 IP/Design Source 导入功能中分别选择：

```text
ip/pango/mes50hp_video_pll/pll.idf
ip/pango/DDR3_50H/DDR3_50H.idf
rtl/vendor/pgl50h/ddr/wr_fram_buf/wr_fram_buf.idf
rtl/vendor/pgl50h/ddr/rd_fram_buf/rd_fram_buf.idf
```

如果当前 PDS 提示 IP 版本迁移，先记录原参数，再用当前版本重新生成，模块名和端口名保持 `pll`、`DDR3_50H`、`wr_fram_buf`、`rd_fram_buf`。DDR3 的器件、数据宽度和存储器参数必须沿用官方 MES50HP 工程，不要使用默认 DDR 配置覆盖。

## 5. 设置顶层与约束

1. 将 `pgl50h_board_top.sv` 设为 Top Module。
2. 禁用或移除旧约束 `boards/pgl50h/pds/pgl50h_rtl_synth/source/clk.fdc`。
3. 加入并启用 `boards/pgl50h/constraints/pgl50h_board_top.fdc`。
4. 确认工程器件仍是 PGL50H/MES50HP 官方例程对应器件。

新 `.fdc` 已包含：

- MES50HP HDMI RX/TX、I2C、LED 管脚；
- MES50HP DDR3 全部管脚、电平和 PHY 位置；
- 50 MHz `sys_clk`；
- 37.125 MHz `pixclk_in`；
- 由 PLL 实现的约 37.121 MHz `video_pixel_clk`；
- 由 PLL 实现的约 9.959 MHz `cfg_clk`；
- DDR3 IP 官方派生时钟约束。

## 6. 首轮运行顺序

依次运行：

```text
Compile
→ Synthesize
→ Device Map
→ Place & Route
→ Report Timing
```

首轮重点检查：

1. 顶层端口均有管脚，且没有旧的 `clk/frame_start/mem_req_*` 虚拟 IO；
2. `DDR3_50H`、PLL、两个帧缓存 IP 没有被当成黑盒；
3. 在综合前，使用 PDS 根据 `ip/pango/mes50hp_video_pll/pll.idf` 重新生成 `clkout0`，目标为 **74.250 MHz**，并保持 `clkout1` 为约 9.959 MHz。当前生成参数对应 `STATIC_RATIO0=11`、`STATIC_RATIOF=49`；`.fdc` 使用 `49/33` 与 `49/246`，以匹配 PDS 的实际整数分频结果。PDS 报告应显示约 74.242 MHz（约 59.994 Hz 的 1650×750 输出）与约 9.959 MHz；
4. 没有 unconstrained clocks；
5. Setup/Hold 均无负裕量；
6. DDR PHY 校准相关布局约束没有实例路径失配；
7. LUT/FF/DRM/APM 使用率保留足够余量。

若 Compile 首先报找不到模块，优先检查第 3、4 节的源文件/IP是否都已导入。若约束报实例不存在，先确认 PDS 在 IP 迁移时是否改了 DDR3 或 PLL 的内部实例层级，不要直接删除 DDR PHY 位置约束。

## 7. 当前硬件行为边界

该版本先完成“单帧采集—单帧矫正—循环显示”，便于没有板卡时进行可控集成，也便于拿到板卡后分阶段排错。输入缓存和算法随机读已经使用 RGBX8888 + Tile Cache；输出帧暂保留已验证的 RGB888 行缓存，以避免在 RGBX 输出读取器具备厂商双时钟 DRM 实现前引入不可综合的整帧数组。

第一次上板建议保持零畸变参数，确认 HDMI 输入、DDR3、算法读写和 HDMI 输出都连通；随后再写入真实相机标定参数。实时连续视频和运行时寄存器配置属于下一阶段优化。

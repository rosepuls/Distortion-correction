# PGL50H HDMI + DDR3 板级工程 PDS 操作清单

## 目标

在现有 `pds/pgl50h_rtl_synth/pgl50h_rtl_synth.pds` 中将算法验证顶层升级为 MES50HP 实物顶层。最终顶层必须是：

```text
pgl50h_board_top
```

文件位置：`rtl/board/mes50hp/pgl50h_board_top.sv`。

## 1. 保留现有算法源文件

保留当前工程中的以下文件：

```text
rtl/distortion/coordinate_gen.sv
rtl/distortion/normalize.sv
rtl/distortion/coordinate_split.sv
rtl/distortion/distortion_core.sv
rtl/distortion/distortion_core_optimized.sv
rtl/interpolation/bilinear_interp.sv
rtl/memory/pixel_fetch_engine.sv
rtl/distortion/distortion_image_pipeline.sv
rtl/board/mes50hp/clock_reset.sv
rtl/board/mes50hp/mes50hp_top.sv
```

`distortion_core.sv` 仍是参数化 generate 分支的编译依赖，首轮 PDS 综合不要删除。

## 2. 加入新的板级 RTL

将以下文件加入 Design Source：

```text
rtl/board/mes50hp/board_video_control.sv
rtl/board/mes50hp/ddr3_pixel_read_adapter.sv
rtl/board/mes50hp/algorithm_frame_writer.sv
rtl/board/mes50hp/ddr3_frame_reader.sv
rtl/board/mes50hp/pgl50h_board_top.sv
```

## 3. 加入官方 HDMI、DDR 调度和视频 RTL

将以下厂商参考 RTL 加入 Design Source：

```text
rtl/vendor/mes50hp/hdmi/iic_dri.v
rtl/vendor/mes50hp/hdmi/ms7200_ctl.v
rtl/vendor/mes50hp/hdmi/ms7210_ctl.v
rtl/vendor/mes50hp/hdmi/ms72xx_ctl.v
rtl/vendor/mes50hp/ddr/wr_buf.v
rtl/vendor/mes50hp/ddr/wr_cmd_trans.v
rtl/vendor/mes50hp/ddr/wr_ctrl.v
rtl/vendor/mes50hp/ddr/rd_ctrl.v
rtl/vendor/mes50hp/ddr/wr_rd_ctrl_top.v
rtl/vendor/mes50hp/video/sync_vg.v
```

不要加入 `sim/models/pgl50h_board_vendor_stubs.sv`。它只用于 XSIM 结构测试，会与真实厂商模块重名。

## 4. 导入四个官方 IP

在 PDS 的 IP/Design Source 导入功能中分别选择：

```text
ip/pango/mes50hp_video_pll/pll.idf
ip/pango/DDR3_50H/DDR3_50H.idf
rtl/vendor/mes50hp/ddr/wr_fram_buf/wr_fram_buf.idf
rtl/vendor/mes50hp/ddr/rd_fram_buf/rd_fram_buf.idf
```

如果当前 PDS 提示 IP 版本迁移，先记录原参数，再用当前版本重新生成，模块名和端口名保持 `pll`、`DDR3_50H`、`wr_fram_buf`、`rd_fram_buf`。DDR3 的器件、数据宽度和存储器参数必须沿用官方 MES50HP 工程，不要使用默认 DDR 配置覆盖。

## 5. 设置顶层与约束

1. 将 `pgl50h_board_top.sv` 设为 Top Module。
2. 禁用或移除旧约束 `pds/pgl50h_rtl_synth/source/clk.fdc`。
3. 加入并启用 `constraints/mes50hp/pgl50h_board_top.fdc`。
4. 确认工程器件仍是 PGL50H/MES50HP 官方例程对应器件。

新 `.fdc` 已包含：

- MES50HP HDMI RX/TX、I2C、LED 管脚；
- MES50HP DDR3 全部管脚、电平和 PHY 位置；
- 50 MHz `sys_clk`；
- 74.25 MHz `pixclk_in`；
- 37.125 MHz `video_pixel_clk`；
- 10 MHz `cfg_clk`；
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
3. `video_pixel_clk` 报告为 37.125 MHz，`cfg_clk` 报告为 10 MHz；
4. 没有 unconstrained clocks；
5. Setup/Hold 均无负裕量；
6. DDR PHY 校准相关布局约束没有实例路径失配；
7. LUT/FF/DRM/APM 使用率保留足够余量。

若 Compile 首先报找不到模块，优先检查第 3、4 节的源文件/IP是否都已导入。若约束报实例不存在，先确认 PDS 在 IP 迁移时是否改了 DDR3 或 PLL 的内部实例层级，不要直接删除 DDR PHY 位置约束。

## 7. 当前硬件行为边界

该版本先完成“单帧采集—单帧矫正—循环显示”，便于没有板卡时进行可控集成，也便于拿到板卡后分阶段排错。它不是实时逐帧视频流水版本。

第一次上板建议保持零畸变参数，确认 HDMI 输入、DDR3、算法读写和 HDMI 输出都连通；随后再写入真实相机标定参数。实时连续视频和运行时寄存器配置属于下一阶段优化。

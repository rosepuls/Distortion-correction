# MES50HP / PGL50H 板卡层

本目录存放 MES50HP/PGL50H 专用 RTL。算法模块不得反向依赖本目录。

## 当前顶层

面向实物板卡的 PDS 顶层是 `pgl50h_board_top`：

```text
pgl50h_board_top
├── 视频 PLL（PDS 重生成后：37.125 MHz / 10 MHz / 可选辅助时钟）
├── MS7200 / MS7210 I2C 初始化
├── HDMI RGB888 输入采集并扩展为 RGBX8888 帧缓存
├── 官方 DDR3 Controller/PHY 和读写仲裁
├── mes50hp_top 畸变矫正算法与 16×4 Tile Cache
├── 矫正结果 DDR3 帧写入器
├── 矫正结果 DDR3 帧读取器
└── 1280×720@30 HDMI 输出时序
```

上电后采用便于首轮上板调试的一次性流程：

```text
等待 PLL、HDMI 和 DDR3 就绪
→ 采集一帧 HDMI 输入到 DDR3
→ mes50hp_top 从 DDR3 取四邻域像素并执行双线性畸变矫正
→ 将矫正结果写到独立 DDR3 帧区
→ 循环输出已矫正帧到 HDMI TX
```

`mes50hp_top.sv` 仍然保留为算法层独立综合和仿真的顶层，但实物工程不要再把它设为最外层。

## 板级模块

| 文件 | 作用 |
| --- | --- |
| `pgl50h_board_top.sv` | 物理 IO、PLL、HDMI、DDR3 与算法整链集成。 |
| `board_video_control.sv` | 等待、采集、处理、显示四阶段控制。 |
| `ddr3_pixel_read_adapter.sv` | 将算法的 RGB888 像素读请求转换为官方 DDR 256-bit 读接口。 |
| `algorithm_frame_writer.sv` | 将算法输出的 RGB888 像素打包为官方 DDR 帧格式。 |
| `ddr3_frame_reader.sv` | 从矫正帧区预取数据，并跨域送给 HDMI 输出。 |
| `mes50hp_top.sv` | 现有畸变坐标、四点取样和双线性插值算法顶层。 |

## 当前固定参数

- 输入帧格式：RGBX8888（`{R,G,B,8'h00}`），以 256-bit 突发供 Tile Cache 读取；
- 输出帧格式：RGB888（已验证的行缓存路径）；
- 输入/输出分辨率：1280×720；
- HDMI 输入像素时钟约束：37.125 MHz；
- HDMI 输出像素时钟：37.125 MHz，对应 720p30；PLL 必须在 PDS 中按 `docs/board/pgl50h_pds_handoff.md` 重新生成；
- Tile Cache：16 sets × 4 ways，32 KiB RGBX Tile Cache；
- 标定初值：`fx=fy=600`、`cx=639.5`、`cy=359.5`、`k1=k2=p1=p2=0`；
- 输入帧使用官方 `wr_buf` 双帧区，矫正结果使用独立的 `OUTPUT_FRAME_BASE` 帧区。

零畸变系数用于首次硬件连通性验证。拿到相机标定结果后，只需修改 `pgl50h_board_top.sv` 的 `CFG_*` 参数，不需要改 DDR/HDMI 接口。

## PDS

完整导入顺序和注意事项见：

`docs/board/pgl50h_pds_handoff.md`

顶层约束文件：

`boards/pgl50h/constraints/pgl50h_board_top.fdc`

该约束由官方 HDMI 与 HDMI+DDR3 例程合并而来，并按当前实例名修正。不要同时启用旧的 `boards/pgl50h/pds/pgl50h_rtl_synth/source/clk.fdc`。

## 仿真

板级结构仿真使用厂商接口桩，只验证模块端口、复位和基本连线，不等价于 DDR3 PHY 时序仿真：

```powershell
.\sim\run_pgl50h_board_top_compile.ps1
```

各适配器和算法图片级回归：

```powershell
.\sim\run_ddr3_pixel_read_adapter.ps1
.\sim\run_algorithm_frame_writer.ps1
.\sim\run_ddr3_frame_reader.ps1
.\sim\run_board_video_control.ps1
.\sim\run_mes50hp_top_image.ps1
```

所有 XSIM 临时文件都写入 `xsim.dir`，图片级结果仍写入 `result/sim_assets`。

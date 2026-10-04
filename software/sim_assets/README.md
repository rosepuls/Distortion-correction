# 仿真图片素材

此目录用于生成无板卡 Pixel Fetch 仿真的输入图，不用于打印相机标定板。

面向 `distortion_core_optimized` 生成 Q18 位精确黄金结果时，在
`generate_distortion_vectors.py` 后添加 `--optimized-q18`。完整的
PGL50H 顶层图片回归可直接运行 `sim/run_mes50hp_top_image.ps1`。

生成 64×48、每格 8 像素的 RGB 棋盘格：

```powershell
py software/sim_assets/create_checkerboard.py --width 64 --height 48 --square-size 8
```

将 PNG 转为 RGB888 `$readmemh` 初始化文件：

```powershell
py software/sim_assets/image_to_mem.py result/sim_assets/checkerboard_64x48.png
```

`.mem` 每行是一个 `RRGGBB` 逻辑像素，地址顺序为：

```text
addr = y * FRAME_STRIDE_PIXELS + x
```

默认 `FRAME_STRIDE_PIXELS` 等于图片宽度。需要行填充时，传入
`--frame-stride-pixels <stride>`；脚本会在每行末尾插入 `000000`，确保
逻辑地址与 DDR 行为模型一致。

默认生成路径统一位于 `result/sim_assets/`。如有需要，仍可通过 `--output`
指定其他输出位置。

## 256×192 彩色畸变图片级回归

一条命令即可生成 32 像素格的彩色棋盘图、`bitaccurate_distortion.py`
对应的 65 位坐标向量和 Golden 图，并执行 RTL Pixel Fetch 仿真：

```powershell
powershell -ExecutionPolicy Bypass -File sim/run_pixel_fetch_distortion_image.ps1
```

输出集中在 `result/sim_assets/`：

- `color_checkerboard_256x192.png/.mem`：RGB 输入图和 DDR 初始化数据；
- `barrel_256x192_coords.mem`：每行
  `coord_valid[64]:x0[63:48]:y0[47:32]:dx[31:16]:dy[15:0]`；
- `golden_barrel_256x192.mem/.png`：Python 定点参考结果；
- `rtl_barrel_256x192.mem/.png`：RTL 仿真结果。

XSim 的日志、快照和临时文件集中在
`xsim.dir/pixel_fetch_distortion_image/`，不会写入项目根目录。

## RTL 畸变坐标整链图片仿真

以下命令不再向 RTL 注入 Python 坐标，而是运行真实的
`coordinate_gen -> distortion_core -> pixel_fetch_engine -> bilinear_interp`：

```powershell
powershell -ExecutionPolicy Bypass -File sim/run_distortion_image_pipeline.ps1
```

最终文件统一位于 `result/sim_assets/full_chain_256x192/`。其中
`full_chain_comparison.png` 依次展示输入图、Python 定点 Golden、RTL 输出和
放大 8 倍的绝对差分图。XSim 临时文件统一位于
`xsim.dir/distortion_image_pipeline/`。

## 畸变输入到 RTL 矫正输出

真正的矫正方向回归使用以下命令：

```powershell
powershell -ExecutionPolicy Bypass -File sim/run_distortion_correction_image.ps1
```

脚本首先从直线棋盘图迭代求 Brown-Conrady 逆映射，生成模拟相机畸变输入，
然后由 RTL 整链矫正。结果集中在
`result/sim_assets/correction_full_chain_256x192/`，其中
`correction_comparison.png` 展示标准图、畸变输入、RTL 矫正结果以及
RTL 与 Python Golden 的放大差分。XSim 临时文件位于
`xsim.dir/distortion_correction_image/`。

## 1280×720 RGBX Cache 回归

当前 PGL50H 主路径使用 1280×720@30fps、16 set × 4 way Tile Cache。完整图片回归使用：

```powershell
powershell -ExecutionPolicy Bypass -File sim/run_mes50hp_top_cache_image_720p.ps1
```

结果位于 `result/sim_assets/cache_full_chain_1280x720/`，吞吐率回归使用：

```powershell
powershell -ExecutionPolicy Bypass -File sim/run_720p30_throughput.ps1
```

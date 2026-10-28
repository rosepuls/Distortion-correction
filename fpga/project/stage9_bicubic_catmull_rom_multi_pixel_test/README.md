# Stage 9 双三次缓存查询流水（第一阶段）

本工程从 `stage9_bicubic_catmull_rom_window_reuse_profile_test` 派生，保留原有水平窗口复用、32 位吞吐诊断和 Fabric Debugger 通道。读取器最多保留两个输出像素上下文，将每个像素需要的 2 次（窗口复用）或 4 次（回退路径）tile cache 查询连续发出，并按 cache 响应顺序组装 4×4 邻域。双三次读取器的外部端口、角度参数传递和插值选择接口保持不变。

## 修改动机

2026-10-27 实板诊断显示输入发布约 59.1 fps、处理输出约 7.1 fps；每帧约 17.9 M 个 125 MHz 周期，其中约 95% 是坐标请求阻塞。`cached_bicubic_neighbor_reader` 之前在每次 cache lookup 后等待该次 response，再发下一笔。本阶段利用 `pixel_tile_cache` 已有的有序响应 FIFO，在一个像素内部并行推进 lookup 发射和响应收集。

## 验证

- `Run-Stage9BicubicReader.ps1`：红绿回归验证。旧 RTL 的热缓存全窗口查询间隔为 7 周期；新 RTL 的 4 笔查询最大间隔为 1 周期。4×4 数据、窗口复用、非连续坐标回退、行切换、边界黑像素、帧起始失效和输出反压均通过。
- `Run-Stage9BicubicFrame.ps1`：64×8 双三次完整帧及严格边界仿真通过。
- PDS 完整综合、布局布线、位流生成成功；当前目录内最终 timing report 为 `All Constraints Met`。DDR PHY 125 MHz 慢角 setup WNS 0.049 ns，hold WHS 0.138 ns。
- 2026-10-28 的 35 秒实板采样中，输入发布 2,110 帧，处理与显示取新帧各 801 帧，约 22.9 fps；该结果见 `docs/chat/camera-calibration.md`。后续优化应使用同条件帧计数比较。

## 当前下载文件

- `.sbit` SHA-256：`63474F045EF12918E53173746D8C7B504647265EDB4740F44B6973371A88F74F`
- `.fic` SHA-256：`B4CB896ED443650531A9EDE33462928791122EEFCE895467FC7D420BA7AF13D5`

两个文件位于 `generate_bitstream/`，必须成对使用。FIC 的设计输入路径指向本工程综合结果。此提交保留当前 `.sbit/.fic` 配对；其他生成目录和日志按仓库 `.gitignore` 规则留在本地。

## 重建

```powershell
.\Build-Stage9Bicubic.ps1 -PdsShell 'D:\Pango\PDS_2022.2-SP6.4\bin\pds_shell.exe'
```

仅复核已生成产物：

```powershell
.\Build-Stage9Bicubic.ps1 -FinalizeOnly
```

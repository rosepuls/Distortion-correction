# 基于紫光同创盘古50 MES50HP（PGL50H）的视频畸变矫正与轻量视觉处理系统项目计划

> 文档状态：已按仓库当前 RTL、仿真脚本与板级集成结构更新（2026-10-06）。
>
> 本文以当前代码为准，区分“已实现”“已验证”和“待完成”。它不是对实物板卡已经通过验收的声明。

## 1. 项目定位与当前目标

本项目面向紫光同创盘古50 MES50HP 开发板，目标器件为 `PGL50H-6IFBG484`。系统以 HDMI 输入的 RGB 图像为源，先将完整输入帧存入 DDR3，再用 Brown–Conrady 反向映射、DDR 随机取样与双线性插值生成校正 RGB 图，最后通过 HDMI 输出。

当前板级主目标固定为：

```text
输入 / 输出：1280 × 720 @ 30 fps
算法 / DDR PHY 参考时钟：100 MHz
HDMI 像素时钟：37.125 MHz（PDS 实例中应按当前 PLL/IP 参数复核）
```

1080p30 是缓存和吞吐的仿真压力基线，不是当前首轮上板验收目标；720p60、1080p60 不在当前主线承诺范围内。

系统不采用 YOLO 或其他深度学习检测网络。轻量视觉处理采用传统、可综合的流式 RTL：灰度化、亮度/伽马、3×3 高斯、Sobel、阈值与形态学。连通域、标靶自动筛选和 ROI 框选尚未进入主板级数据通路。

## 2. 当前实现状态

### 2.1 已实现并纳入代码库

| 子系统 | 当前实现 | 关键位置 |
|---|---|---|
| 畸变坐标 | 基线核心与推荐的 Q18 优化 Brown–Conrady 核心；帧首锁存标定参数 | `rtl/algorithm/distortion/` |
| 重采样 | 坐标拆分、四邻域逻辑像素读取、RGB 三通道 Q0.16 双线性插值 | `coordinate_split.sv`、`pixel_fetch_engine.sv`、`bilinear_interp.sv` |
| DDR 取数优化 | RGBX8888、256-bit DDR 数据拍、16 set × 4 way Tile Cache、突发读取 | `rtl/platform/common/memory/` |
| 预处理/检测模块 | RGB2Gray、Brightness/Gain、双 bank Gamma LUT、3×3 窗口、高斯、Sobel、Threshold、Morphology | `rtl/algorithm/preprocess/`、`rtl/algorithm/detect/` |
| 板级框架 | PGL50H 物理顶层、HDMI I²C 初始化、DDR3 适配、输出写帧/读帧、时钟/复位 | `rtl/board/pgl50h/` |
| 连续帧控制 | 双输入帧区、双输出帧区的调度器；读/写两客户端事务锁定仲裁；显示端帧边界切换 | `realtime_frame_scheduler.sv`、`ddr_two_client_arbiter.sv`、`pgl50h_board_top.sv` |
| 软件与自动化 | 浮点/位精确模型、缓存与地址轨迹模型、XSim 单元、图片级和吞吐回归脚本 | `software/`、`sim/` |

### 2.2 当前板级主链

```text
HDMI RX RGB888
  → 输入写缓冲（RGBX8888）
  → DDR3 输入帧 A/B
  → Tile Cache / 畸变坐标 / 四邻域读取 / 双线性插值
  → DDR3 输出帧 C/D
  → 显示端在帧边界选择已完成的输出 bank
  → HDMI TX RGB888
```

算法侧的 `mes50hp_top.sv` 负责一帧输出光栅、畸变流水和逻辑像素读接口；只有 `pgl50h_board_top.sv` 连接 HDMI、DDR3、PLL、I²C 与物理 IO，因此 PDS 工程必须将后者设为顶层。

### 2.3 已验证的范围与边界

- 优化畸变核心已具备 Python Q18 黄金向量与 XSim 回归。
- `mes50hp_top` 已有 256×192 RGB888 图片级 XSim：输出 49,152 像素，且与位精确 Python 输出逐像素一致。
- 720p30、1080p30 的 Cache/吞吐脚本和板级结构仿真脚本已存在；其中 1080p30 压力模型报告为模型结果，不可等价为板上实时性能。
- 最新工程已包含连续帧调度与仲裁 RTL；它们仍须在当前机器恢复 XSim 生成 C 文件编译后重新执行对应回归。
- 当前本机执行 `sim/run_realtime_frame_scheduler.ps1` 时，Vivado 2020.2 在 `xelab` 的生成 C 文件编译阶段失败，尚未进入 testbench 的 `TEST_PASS` 断言。这是验证工具链异常，不能据此推断调度器 RTL 功能失败。
- PDS 综合、布局布线、DDR3 校准、HDMI 收发、时钟/复位可靠性与长时间连续视频稳定性，均必须在 PDS 与实物板卡上单独验收。

## 3. 设计边界和关键约束

### 3.1 算法与板级分层

```text
rtl/algorithm/          板卡无关的图像与畸变算法
rtl/platform/common/    逻辑像素访问、缓存与算法控制基础设施
rtl/board/pgl50h/       MES50HP 专用顶层、DDR 适配、视频与控制
rtl/vendor/pgl50h/      官方 HDMI/DDR/视频参考 RTL 与封装
boards/pgl50h/          PDS 工程、IP、约束与上板文件
```

不得将 PDS 原语、DDR3 AXI 端口或 HDMI 管脚传播进 `rtl/algorithm/`。新板卡适配应增加新的 `board/<board>` 和 `vendor/<board>` 目录，而不改动已经验证的算法接口。

### 3.2 帧存储和一致性

输入使用 DDR3 区域 A/B，输出使用互不重叠的区域 C/D。输入帧完整写入后才可以启动对该 bank 的随机读取；输出 bank 仅在整帧写完后通过 CDC 通知显示端，显示端只在下一输出帧边界切换 bank。

这保证：

- 算法不会读取正在采集的输入帧；
- 算法不会覆盖仍可能被随机读取的源帧；
- HDMI 不会读取正在写入的输出帧；
- 算法忙时若没有可用输入 bank，必须报告 `input_overrun`，不得静默覆盖。

### 3.3 像素格式和有效边界

- 输入帧：RGBX8888，便于映射为 256-bit DDR burst 与 Tile Cache 行。
- 校正算法输入/输出：RGB888。
- 输出帧：当前 RGB888 行缓存写读路径。
- 双线性插值仅在 `0 <= x0 < width-1`、`0 <= y0 < height-1` 时读取四邻域；无效坐标输出黑色。
- 所有帧级配置在 `sof` 锁存，不允许在同一有效帧中变更标定参数、阈值、伽马 bank 或预处理开关。

### 3.4 时钟与 CDC

系统至少涉及 HDMI 输入像素、DDR3 用户/核心、算法、HDMI 输出像素和配置时钟域。单 bit 控制跨域使用双触发器或握手；像素流与帧数据跨域使用 FIFO、帧缓存或官方双口 RAM；每个时钟域独立同步释放复位。

`output_ready_toggle` 仅用于传递“输出帧完成”事件；输出 bank 的真实切换必须在 HDMI 输出帧起点执行。不要假设 HDMI 输入、输出、DDR 用户时钟同频同相。

## 4. 已实现的算法路线

### 4.1 畸变矫正与重采样

采用反向映射，输出坐标 `(u,v)` 反求原始畸变帧中的 `(src_x,src_y)`：

```text
coordinate_gen
  → distortion_core_optimized
  → coordinate_split
  → cached_pixel_fetch_engine
  → bilinear_interp
```

优化核心实现径向 `k1/k2` 与切向 `p1/p2` 项；使用 Horner 形式降低乘法链宽度。`coordinate_split` 将 Q13.19 源坐标转换为 `x0/y0` 与 Q0.16 的 `dx/dy`，再由双线性插值重建 RGB888 像素。

首轮板级连通性参数为零畸变：`fx=fy=600`、`cx=639.5`、`cy=359.5`、`k1=k2=p1=p2=0`。它们只用于通路验证；拿到实际相机与镜头后，必须由标定结果替换，并归档原始图、内参、畸变系数、重投影误差与量化后的 FPGA 配置。

### 4.2 Cache 与吞吐策略

当前 720p30 实现选用 `16 set × 4 way` RGBX Tile Cache（约 32 KiB），以减少直接四次随机读的 DDR 压力。1080p30 的 `32×4` tile、`16 set × 8 way` 是独立压力基线，不能倒灌为当前 720p30 的资源配置。

缓存、请求 FIFO 和复位树已在算法域拆分；Cache 的 tag/valid 与 FIFO 指针复位，数据负载寄存器可以保留旧值但不得在无效状态被读取。新输入帧开始时应失效旧 Cache tag，防止跨帧命中。

### 4.3 轻量视觉处理链

已实现、但尚未实例化进 `pgl50h_board_top.sv` 的推荐处理链为：

```text
校正 RGB888
  → rgb2gray
  → brightness_gain（可旁路）
  → gamma_lut（可旁路）
  → line_buffer_3x3 + window_3x3
  → gaussian_3x3
  → 第二组 line_buffer_3x3 + window_3x3
  → sobel_3x3
  → threshold
  → 第三组 1-bit line_buffer_3x3 + window_3x3
  → morphology
```

高斯后的 Sobel、以及阈值后的形态学都需要各自的 3×3 窗口；不能复用不同像素流上的同一个窗口实例。当前 HDMI 输出只能认定为“校正 RGB”，不是边缘图、二值图或 ROI 叠加图。

## 5. 当前阶段的任务顺序

### 阶段 A：恢复并固定仿真回归环境

目标是使最新连续帧 RTL 的回归结果可复现，而非修改算法功能。

1. 定位 Vivado 2020.2 生成 C 文件编译失败的主机依赖或环境差异，保留完整 `xelab` 日志。
2. 恢复后依次运行：

   ```powershell
   .\sim\run_realtime_frame_scheduler.ps1
   .\sim\run_ddr_two_client_arbiter.ps1
   .\sim\run_pgl50h_board_top_compile.ps1
   .\sim\run_720p30_throughput.ps1
   .\sim\run_mes50hp_top_cache_image_720p.ps1
   ```

3. 所有脚本必须出现各自的 `TEST_PASS:` 标记；720p 图片回归还必须确认 921,600 像素与黄金图逐像素一致。
4. 更新日期、Vivado 版本、命令、日志位置和结果到验证报告；工具链未恢复前不把连续帧模块标记为“本机已回归”。

### 阶段 B：PDS 可综合工程与器件级收敛

1. 打开 `boards/pgl50h/pds/pgl50h_rtl_synth/pgl50h_rtl_synth.pds`，将顶层设为 `pgl50h_board_top`。
2. 根据 `docs/board/pgl50h_pds_handoff.md` 导入算法、板级、官方 HDMI/DDR RTL 以及 PLL、`DDR3_50H`、读写帧缓存 IP。
3. 只启用 `boards/pgl50h/constraints/pgl50h_board_top.fdc`，不要与旧 `clk.fdc` 同时使用。
4. 依次完成 Compile、Synthesize、Device Map、Place & Route、Report Timing。
5. 归档 PDS 版本、器件/IP 版本、源文件清单、约束、资源、未约束时钟、Setup/Hold 和关键路径；在实板验证前仅称为“器件级结果”。

验收条件：没有缺失模块/IP 黑盒、没有未约束时钟、Setup/Hold 无负裕量，并留有 HDMI、DDR、调试和后续预处理集成所需的资源余量。

### 阶段 C：首轮上板连通性

按风险从低到高执行，不在首次下载时同时引入真实畸变和检测链：

```text
JTAG / LED
→ PLL 锁定与各域复位
→ MS7200/MS7210 I²C 初始化
→ 720p30 Color Bar / 输出时序
→ HDMI RGB888 输入采集
→ DDR3 校准与连续读写
→ 零畸变单帧校正并循环显示
→ 零畸变连续帧采集、处理与显示
→ 真实标定参数畸变校正
```

对每步记录输入源、显示器状态、DDR 初始化状态、`underflow`、`overflow`、`input_overrun`、实际分辨率与持续运行时间。出现问题时先保存波形/状态，不直接改动已通过图片回归的算法定点格式。

### 阶段 D：把轻量视觉处理并入板级主链

这一阶段需要先确定 HDMI 输出产品形态，至少选择一种并为其他模式保留帧间切换接口：

- 校正 RGB；
- 灰度/边缘/二值检测图；
- 校正 RGB 叠加边缘或 ROI。

建议先完成“校正 RGB + 可选边缘叠加”，再决定是否加入连通域、Bounding Box 与标靶筛选。集成时必须补齐第二、第三组 3×3 窗口，并对新增链路重新检查 `valid/sof/eol` 延迟对齐、帧尾冲刷时间和 HDMI 输出格式。

### 阶段 E：真实相机标定与效果评价

1. 使用棋盘格或圆点阵列采集真实相机图像；保存原图和标定脚本版本。
2. 得到 `fx/fy/cx/cy/k1/k2/p1/p2`、重投影误差和最终 FPGA 定点配置。
3. 比较矫正前后直线、格点/角点位置、黑边范围、坐标误差、像素 MAE/MSE/PSNR。
4. 对 720p30 连续视频记录端到端帧率、丢帧/过载、DDR/显示异常和至少一次长时间稳定运行结果。

## 6. 验收口径

| 项目 | 当前验收口径 |
|---|---|
| 算法数学正确性 | Python 浮点与位精确模型，关键向量和图片级像素比较通过 |
| 畸变 RTL | 优化核心、坐标拆分、插值及无效坐标黑边行为与黄金模型一致 |
| 720p30 仿真 | 输出 921,600 像素；图片级比较通过；吞吐符合脚本预算 |
| 连续帧控制 | 调度、仲裁、输入/输出 bank 所有权、显示帧边界切换在单元/结构仿真中通过 |
| PDS 器件级 | 源文件/IP/约束完整，资源与时序报告可追溯，不替代板测 |
| 板级连通性 | HDMI 输入、DDR3、畸变校正帧写回、HDMI 输出在零畸变下稳定工作 |
| 实际矫正效果 | 基于真实镜头标定参数的标靶/直线效果与定量指标，而非人工参数截图 |
| 视觉处理 | 若纳入最终演示，必须完成板级集成、模式定义、同步对齐与图像结果验证 |

## 7. 明确不应混淆的结论

- XSim 行为/图片仿真通过，不证明 DDR3 PHY、HDMI 芯片、引脚或真实时钟可靠。
- PDS 布局布线通过，不证明视频链路在实板可长期稳定运行。
- 1080p30 Cache/压力模型通过，不等同于该板卡已达到 1080p30 实测。
- 当前预处理模块已完成，不等于它们已经在 HDMI 输出路径中运行。
- 当前连续帧 RTL 已实现，不等于它已在本机 XSim 或实板完成最终验证。

## 8. 主要文档入口

- 板级导入与约束：[PDS 操作清单](../board/pgl50h_pds_handoff.md)
- 引脚、时钟和板卡资源：[board 文档](../board/)
- RTL 分层和模块职责：[RTL 模块总览](../../rtl/guide/RTL模块总览.md)
- 预处理链接线与时序：[预处理 RTL 集成说明](../preprocess_rtl_integration.md)
- 缓存与吞吐报告：[1080p30 吞吐报告](../reports/1080p30_throughput_report.md)
- 连续帧设计基线：[实时帧管线设计](../superpowers/specs/2026-10-05-pgl50h-realtime-frame-pipeline-design.md)

## 9. 当前下一项实际工作

优先完成“阶段 A：恢复最新连续帧 RTL 的可复现仿真回归”，随后进入 PDS 器件级实现。实物板卡具备后，再按阶段 C 的连通性顺序上板。轻量视觉处理链的板级接入应在畸变主链稳定后开展，避免同时引入算法同步、DDR、HDMI 和相机标定多重变量。

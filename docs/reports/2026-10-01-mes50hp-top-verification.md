# MES50HP / PGL50H 可综合顶层验证报告

日期：2026-10-01

## 交付范围

- 可综合系统顶层：`rtl/board/mes50hp/mes50hp_top.sv`
- 复位同步模块：`rtl/board/mes50hp/clock_reset.sv`
- 畸变坐标计算、DDR 像素读取、双线性插值整链连接
- RGB888 输出时序：`out_valid`、`out_sof`、`out_eol`
- 帧控制：`frame_start`、`frame_busy`、`frame_done`
- 面向后续 PDS 集成的逻辑 DDR 请求/响应边界

板级 DDR3 PHY、HDMI 接收/发送芯片驱动和具体管脚约束不在本次无板卡交付范围内，需在 PDS 中结合 MES50HP 官方例程接入。

## 验证结果

### Python 回归

命令：

```powershell
py -m unittest discover -s tests -v
```

结果：`Ran 64 tests`，`OK (skipped=4)`。4 项跳过测试依赖当前环境未安装的 Icarus Verilog。

### 优化畸变核心 XSim

- 向量数：25
- 覆盖普通坐标、内部位宽溢出保护和 256x192 图像参数
- 结果：`TEST_PASS: distortion_core_optimized golden_vectors count=25`
- 日志：`xsim.dir/distortion_core_optimized_review/xsim.log`

### MES50HP 顶层图片级 XSim

- 图像尺寸：256x192 RGB888
- 时钟：50 MHz
- 输入：Python 生成的相机畸变棋盘图
- 输出：RTL 畸变矫正图
- 输出像素：49152
- 仿真周期：1179657
- 结果：`TEST_PASS: mes50hp_top_image outputs=49152 cycles=1179657`
- RTL 输出与位精确 Python 黄金模型逐像素一致：`PASS: RGB888 frames match (256x192)`
- 日志：`xsim.dir/mes50hp_top_image_256x192/xsim.log`
- 图像结果：`result/sim_assets/mes50hp_top_image_256x192/mes50hp_top_correction_comparison.png`

测试还覆盖了 DDR 请求反压、请求地址在停顿期间保持稳定、运行中重复 `frame_start` 被忽略、`frame_done` 单周期对齐、地址越界和复位/空闲阶段未知态检查。

### 兼容性回归

原有 `distortion_image_pipeline` 默认仍使用基线核心；新增参数只在 MES50HP 顶层选择优化核心。原图片级回归继续通过：

- `TEST_PASS: distortion_correction_image`
- `PASS: RGB888 frames match (256x192)`

## PDS 接入

1. 按 `rtl/board/mes50hp/README.md` 的顺序加入 RTL 源文件。
2. 将综合顶层设置为 `mes50hp_top`。
3. 对端口 `clk` 使用 20 ns 周期约束（50 MHz）。
4. 先完成 RTL 综合并检查资源、最高频率和关键路径。
5. 板卡到位后，使用官方例程把逻辑 DDR 接口替换为 DDR3 控制器，并接入 HDMI/摄像头时序及真实管脚约束。


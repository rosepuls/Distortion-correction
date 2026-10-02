# 256×192 RTL 畸变整链图片仿真设计

## 目标

使用现有 256×192 RGB 彩色棋盘图，验证以下真实 RTL 数据链：

```text
coordinate_gen -> distortion_core -> pixel_fetch_engine -> bilinear_interp
```

DDR 由已有行为模型代替。Python 定点模型只生成 Golden 参考图，不向 RTL
提供坐标，从而确认坐标计算和像素采样均由 RTL 完成。

## 顶层接口与流控

新增 `rtl/distortion/distortion_image_pipeline.sv`，输入采用
`in_valid/in_ready/in_sof/in_eol` 帧扫描事务，内部实例化现有四个 RTL 模块。
由于 `distortion_core` 无反压而 `pixel_fetch_engine` 当前一次只处理一个像素，
顶层只允许一个坐标处于畸变流水中。只有畸变流水空闲且 Pixel Fetch 空闲时
才拉高 `in_ready`。该策略优先验证功能正确性，不声明 1 Pixel/Clock 吞吐。

顶层向外暴露现有逻辑像素地址请求/响应接口，供
`ddr_behavior_model.sv` 连接；输出为 RGB888 及 `valid/sof/eol`。

## 固定仿真配置

- 图像：256×192 RGB 彩色棋盘格，格宽 32 像素。
- 相机：`fx=fy=180.0`，`cx=127.5`，`cy=95.5`。
- 畸变：`k1=-0.25`，`k2=0.05`，`p1=0.001`，`p2=-0.001`。
- 定点格式：沿用 `docs/numeric_spec.md`。
- 边界：四邻域无效时输出黑色。

## 文件与输出隔离

- Testbench：`sim/tb_distortion_image_pipeline.sv`。
- 一键脚本：`sim/run_distortion_image_pipeline.ps1`。
- XSim 临时目录：`xsim.dir/distortion_image_pipeline/`。
- 最终资产目录：`result/sim_assets/full_chain_256x192/`。

最终目录包含输入 PNG/MEM、Python Golden PNG/MEM、RTL PNG/MEM、坐标诊断
MEM，以及输入/Golden/RTL/差分四宫格 PNG。RTL Testbench 内部逐像素比较，
仿真结束后 Python 再做一次完整帧比较。

## 验收条件

1. XSim 输出 `TEST_PASS: distortion_image_pipeline`。
2. RTL 与 Python Golden 的 49,152 个 RGB888 像素逐位相同。
3. `sof/eol` 与首像素及每行末像素严格对齐。
4. 项目完整 Python 回归无新增失败。
5. 项目根目录不新增 XSim 临时文件。

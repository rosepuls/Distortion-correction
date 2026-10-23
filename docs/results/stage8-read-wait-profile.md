# Stage 8 DDR 读等待诊断

## 目的

Stage 7 16×8 实板为 31.28 fps，但原有 AR 等待计数把仲裁等待与 DDR `ARREADY` 反压合在一起，读响应等待也没有区分首拍延迟和拍间空隙。Stage 8 保持 Stage 7 16×8 数据通路与固定映射，只添加四类等待计数，供下一步决定是否实现多笔未完成读。

## 新计数定义

- `perf_read_arbiter_wait_cycles`：处理读请求已准备好，但已有读事务未结束，或显示端请求先获仲裁。
- `perf_read_arready_wait_cycles`：处理端获得 AR 选择，但 DDR 尚未接受该地址。
- `perf_read_first_beat_wait_cycles`：AR 握手后等待当前行第一拍 R 数据。
- `perf_read_interbeat_wait_cycles`：收到第一拍后等待该行后续 R 数据。

地址等待两项划分原 AR 等待；首拍和拍间两项划分原读响应等待。四类值按单帧记录；24 位计数在 125 MHz 下约 134 ms 饱和。等待项之间仍可能与坐标反压或缓存填充窗口重叠，不应直接相加作为帧周期。

### Stage 8 FIC 通道

Stage 8 的 256 位 Fabric DebugCore 通道已满，因此诊断工程复用 Stage 7 的部分通道。本工程通道表与 Stage 7 不同：

| 通道 | Stage 8 信号 |
|---|---|
| 0–63 | 输入发布、处理完成、显示取新帧、输入丢帧计数 |
| 64–79 | 错误标志 |
| 80–103 | 最近完成帧周期 |
| 104–127 | 仲裁等待 |
| 128–151 | 缓存未命中次数 |
| 152–175 | 缓存填充周期 |
| 176–199 | DDR `ARREADY` 等待 |
| 200–223 | 读响应首拍等待 |
| 224–247 | 读响应拍间等待 |
| 248–255 | pipeline 状态 |

因此不能用 Stage 7 的 `.fic` 读取 Stage 8，也不能用 Stage 8 的 `.fic` 解释 Stage 7 的采样。

## 仿真和构建

- `Run-DdrReadBurstArbiter.ps1`：PASS，覆盖已有读事务占用、另一客户端被选中、DDR 地址反压三种等待归属。
- `tile_row_ddr_adapter_tb.sv`：PASS，覆盖首拍等待、拍间等待与总响应等待分类。
- `Run-FrameIdentityTransformEngine.ps1`：PASS，完整帧状态机仍完成两帧数据传输。
- `Run-Stage6RadialPipeline.ps1`：PASS，现有映射、缓存读取和元数据检查正常。
- PDS 2022.2-SP6.4 全流程生成位流成功；时序报告 `Design Summary : All Constraints Met`，125 MHz `ddrphy_sysclk` WNS 为 +0.191 ns。

位流：`fpga/project/stage8_read_wait_profile/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`  
SHA-256：`AF1B7382C7D775615D5DACF6DB33690D1CEC5842E3135F94BABE1394DDD9ACF9`  
配套 FIC：`fpga/project/stage8_read_wait_profile/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic`  
SHA-256：`70DE0F53B9476CF339F7A7FC8F43CA617ACFF7442F442EE87DDDB71D100184D7`

上板步骤和通道定义见 `fpga/project/stage8_read_wait_profile/README_JTAG.md`。烧录后使用同一动态 720p60 输入，间隔约 60 秒采两次 Listing。帧率计数器是累计值；四类等待和帧周期是各快照时最近完成帧的值。需要回退时重新烧录 Stage 7 16×8 的 `.sbit` 并导入它配套的 `.fic`。

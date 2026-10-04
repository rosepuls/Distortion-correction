# 720p30 Cache Resource Reduction Design

## Goal

将 PGL50H 视频畸变矫正主路径切换为原生 1280×720@30fps 输入/输出，并将 Tile Cache 缩减为 16 set × 4 way，在保持 RGBX8888、256-bit DDR burst 和每像素持续处理能力的前提下降低 DRM、Tag 比较和布局布线压力。

## Scope

- 板级默认图像尺寸改为 1280×720。
- 输出视频时序改为 CEA 风格 720p30，像素时钟 37.125 MHz。
- Tile Cache 使用 16 set × 4 way、32×4 Tile、4 个 128-bit Bank。
- Bank 存储深度由固定 2048 word 改为按配置计算；目标配置为 512×128 bit/Bank。
- 保留 256-bit DDR 读突发、Cache miss 完整 Tile 填充、帧间失效和现有算法流水线接口。
- 新增 1280×720 图片仿真和吞吐率回归，保留 1080p 回归脚本作为历史基线。
- 不执行 PDS 综合、布局布线或 PLL 生成；提供对应的 RTL、脚本和约束修改。

## Architecture

相机直接提供 1280×720@30fps 像素流，板级输入写入 RGBX8888 DDR 帧缓存。算法核心以 100 MHz 工作，通过 16×4 Tile Cache 从 DDR 获取畸变采样所需的 32×4 Tile，输出仍写回 RGB888 帧缓存并由 720p30 显示时序读取。

Cache 每个 Bank 的地址宽度由 `SET_COUNT × WAYS × BANK_WORDS_PER_TILE` 自动计算。对于 16×4 配置，该值为 512，因此 Bank 使用 9-bit 地址而不是原来的 11-bit 地址。四个 Bank 的接口宽度与 DDR burst 组织保持不变，避免改变上层协议。

替换策略使用面向 4-way 的 3-bit PLRU。Tag/valid/替换元数据按小容量配置实现为紧凑寄存器结构，避免为小数组推断大量零碎 LUTRAM。Cache 命中仍允许每周期接收一组查找请求；Cache miss 仍由原有 DDR burst reader 完整填充后重试。

## Video timing

720p30 使用：

- H total 1650，H active 1280，H sync 40，H back 220，H front 110；
- V total 750，V active 720，V sync 5，V back 20，V front 5；
- pixel clock 37.125 MHz。

畸变模型的焦距和主点按 1920×1080 到 1280×720 的 2/3 比例缩放，畸变系数保持不变。

## Verification

- 运行 1280×720 full-chain RGBX Cache 图片回归。
- Golden 与 RTL 输出逐像素比较，输出文件尺寸必须为 921600 像素。
- 检查帧开始、行结束、输出像素数和 Cache miss/DDR burst 完成状态。
- 运行 720p30 吞吐率回归；目标算法周期不超过 2,500,000，硬约束预算为 3,333,333 周期。
- 运行已有 Cache、DDR reader、坐标 FIFO、板级编译和结构检查脚本。
- PDS 由用户后续执行；PLL 需在 PDS 中重新生成为 37.125 MHz。

## Compatibility

1080p 源文件、回归脚本和结果目录不删除。720p 使用独立入口和 `cache_full_chain_1280x720` 结果目录，避免覆盖已完成的 1080p 基线。

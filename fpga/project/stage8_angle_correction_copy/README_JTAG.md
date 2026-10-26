# Stage 8 Y 坐标偏移诊断

当前 `generate_bitstream` 中的 `.sbit` 与 `.fic` 必须成对使用。本版将单应输出探针替换为 Brown stage8 校正前的 Y 位移 `total_y8` 及其像素 ID，以判断 +384 像素偏移是在 Brown 校正量乘法前还是乘法中出现。Brown stage9、最终坐标及坐标 FIFO 输出保留像素 ID，便于流水线停顿时逐像素对齐。

## 通道表

| 通道 | 信号 | 含义 |
|---|---|---|
| 0–11 | `fram_buf/copied_count[11:0]` | 已完成处理帧计数低 12 位 |
| 12–43 | `.../angle_and_brown_mapping.lens/total_y8[31:0]` | Brown 校正前归一化 Y 位移，Q16.16 |
| 44–63 | `.../angle_and_brown_mapping.lens/debug_y8_pixel_id[19:0]` | 对应 `total_y8` 的目标像素 ID |
| 64–96 | `.../lens/dy0[32:0]` | Brown 输入 Y 减主点 `cy`，有符号 Q16.16 |
| 97–116 | `.../lens/debug_mapped_pixel_id[19:0]` | 对应 `mapped_y10` 的目标像素 ID |
| 117–148 | `.../lens/y9[31:0]` | Brown 输出加法前延迟的原始 Y，Q16.16 |
| 149–168 | `.../lens/debug_y9_pixel_id[19:0]` | 对应 `y9` 和 `correction_y9` 的目标像素 ID |
| 169–200 | `.../lens/correction_y9[31:0]` | Brown Y 校正量，Q16.16 |
| 201–232 | `.../lens/mapped_y10[31:0]` | Brown 最终 Y 坐标，Q16.16 |
| 233–252 | `.../coord_pixel_id[19:0]` | 坐标 FIFO 输出 ID，与最终 `sy` 对齐 |
| 253 | `.../coord_geometry_valid` | 最终坐标映射有效 |
| 254 | `.../plan_geometry_valid` | 边界规划有效 |
| 255 | `.../lens/geometry10` | Brown 最终结果有效 |

完整层级路径在同目录 FIC 中。像素 ID 按 `y * 1280 + x` 编码；Q16.16 像素值除以 65536 换算。

## 如何判定偏移从哪一级出现

1. 用 `debug_y8_pixel_id` 对齐 `total_y8`，检查负 Y 归一化坐标下的 Brown 位移是否符合定点模型。
2. 用 `debug_y9_pixel_id` 对齐 `y9` 和 `correction_y9`。若 `total_y8` 合理而 `correction_y9` 出现约 `+384` 像素偏移，问题就在 stage8 到 stage9 的像素尺度乘法/有符号结果路径。
3. 用 `debug_mapped_pixel_id` 对齐 `mapped_y10`：应满足 `mapped_y10 = y9 + correction_y9`。
4. 用 `coord_pixel_id` 对齐坐标 FIFO 输出与边界规划结果。若 Brown 最终坐标正确而规划仍失效，问题就在 Brown 输出到 FIFO 的传递或级间对应关系。

现有采样显示黑区与源坐标 Y 固定偏大 384 像素有关。新采集请覆盖黑区起点前后，并保留连续 Listing 数据；比较各级时按像素 ID 对齐。

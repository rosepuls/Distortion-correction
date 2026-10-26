# Stage 8 Brown Y 坐标探针

`generate_bitstream/` 中的 `.sbit` 与 `.fic` 应成对导入。像素 ID 为 `y * 1280 + x`；Q16.16 坐标值除以 65536 得到像素值。各级流水线按对应的 `debug_*_pixel_id` 对齐，不能直接比较同一 Listing 行的不同级。

| 通道 | 信号 | 含义 |
|---|---|---|
| 0–11 | `fram_buf/copied_count[11:0]` | 完成帧计数低位 |
| 12–43 | `.../lens/total_y8[31:0]` | Brown 归一化 Y 位移 |
| 44–63 | `.../lens/debug_y8_pixel_id[19:0]` | `total_y8` 对应目标像素 ID |
| 64–96 | `.../lens/dy0[32:0]` | 原始 Y 减主点 `cy` |
| 97–116 | `.../lens/debug_mapped_pixel_id[19:0]` | `mapped_y11` 对应目标像素 ID |
| 117–148 | `.../lens/y10[31:0]` | 映射加法前的原始 Y |
| 149–168 | `.../lens/debug_y10_pixel_id[19:0]` | `y10`、`correction_y10` 对应目标像素 ID |
| 169–200 | `.../lens/correction_y10[31:0]` | 恢复符号后的 Y 校正量 |
| 201–232 | `.../lens/mapped_y11[31:0]` | Brown 最终 Y 坐标 |
| 233–252 | `.../coord_pixel_id[19:0]` | 坐标 FIFO 输出像素 ID |
| 253 | `.../coord_geometry_valid` | 最终坐标有效 |
| 254 | `.../plan_geometry_valid` | 边界规划有效 |
| 255 | `.../lens/geometry11` | Brown 结果有效 |

目标像素 `0x8F076` 是 `x=886,y=457`。先在其附近触发，再分别用 `debug_y8_pixel_id` 和 `debug_y10_pixel_id` 查找同一像素；对 `total_y8` 按 `FY_Q16` 计算应有的校正量，检查 `correction_y10`。随后以 `debug_mapped_pixel_id` 查 `mapped_y11`，并用 `coord_pixel_id` 核对规划结果。完整层级路径和每一位的通道定义见 `debug_core.fic`。

# Stage 11 自适应图像增强接口

## 状态

Stage 11 RTL 已按此接口接入曲线编号解析、帧边界参数切换和输出像素 LUT。尚未重新构建/烧录 Stage 11 位流，也未执行 RTL 仿真或时序检查；当前板上位流不可发送非零曲线编号。Stage 8 K3 基准仍要求扩展字节 43–62 全零。

## UART 请求与响应

保持现有协议版本 `02` 和固定 65 字节帧，不改变矩阵字段、序号、flags 或 CRC 算法：

| 偏移 | 长度 | 定义 |
|---:|---:|---|
| 0–1 | 2 | 同步字 `A5 5A` |
| 2 | 1 | 版本 `02` |
| 3 | 1 | 请求 `01`；响应 `81` |
| 4–5 | 2 | 小端序号／参数版本 |
| 6 | 1 | 请求 flags；bit 0 为 `pose_valid`，其余位必须为零；响应为状态码 |
| 7–42 | 36 | 9 个 row-major 单应矩阵系数，沿用现有 Q16.16/Q2.30 格式 |
| 43 | 1 | `enhancement_profile_id`，合法值 0–5 |
| 44–62 | 19 | 保留，必须全部为零 |
| 63–64 | 2 | CRC-16/CCITT-FALSE，高字节在前 |

CRC 仍覆盖偏移 2–62。响应回显序号、矩阵和扩展字段。状态码沿用现有定义；`06` 表示保留字节非零，新增 `07` 表示曲线编号超出 0–5。旧版本 02 的全零扩展请求等价于选择 `0:bypass`。

## 参数同步与像素接口

- `enhancement_profile_id` 与同一 UART 请求中的单应矩阵、pose-valid 标志共享 pending 参数组。
- 参数校验成功后写入 pending；在下一输出帧起始处一次性切换 active。复位曲线为 `0:bypass`。
- 像素路径使用 3 位帧锁存的 `active_profile_id`，RGB 三通道读取同一条 256×8 LUT，RGBX 低字节保持原样。复用现有结果 `valid/ready` 握手，不增加独立流水级，像素 ID、帧 ID、参数版本、SOF/EOL/EOF 元数据保持原管线对齐。
- 当前 LUT 位于双线性插值之后、结果写入 DDR 之前，不增加 DDR 读写。若竞赛规则要求几何矫正前预处理，再改到输入像素路径并锁存对应输入帧曲线版本。

## 曲线表和主机职责

曲线配置保存在 `host/pose/lighting_curve_parameters.json`。ID 和名称固定为 `0:bypass`、`1:night`、`2:night_strong`、`3:highlight`、`4:highlight_strong`、`5:mixed`。修改 gamma、knee 或 shoulder power 后，运行 `python host/pose/generate_lighting_lut_rom.py` 生成 Stage11 RTL ROM，并运行 `python host/pose/compare_lighting_curves.py` 更新离线对照。重拍后替换样本目录、调整该 JSON 并重跑即可不改变 UART 或像素接口。

实时上位机仍由单一进程独占 UART；光照选择和角度矩阵共用同一个递增序号、请求帧与 ACK。脚本从未经增强的输入帧做光照分类，增强后的输出不能反馈给分类器。

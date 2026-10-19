# RTL 模块边界

- `video/`：HDMI 输入和输出，后续加入 720p60 时序与跨时钟 FIFO。
- `memory/`：帧槽管理、DDR3 适配和图块缓存。阶段 2 再接入。
- `correction/`：逆向坐标映射、边界判断、双线性插值。阶段 4 再接入。
- `control/`：标定参数、UART 包接收和帧边界更新。阶段 3–5 再接入。

当前 `video/hdmi_loop.v` 是阶段 1 的可综合顶层；它与厂商 HDMI 配置模块和 PG2L200H 配置 PLL 一起组成 PDS 工程。

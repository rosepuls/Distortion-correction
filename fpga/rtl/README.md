# RTL 模块边界

- `video/`：HDMI 输入和输出，后续加入 720p60 时序与跨时钟 FIFO。
- `memory/`：帧槽管理、DDR3 适配和图块缓存。`memory/frame_pool_manager.v` 是三槽所有权管理器；`memory/frame_pipeline_ownership.v` 在 DDR 时钟域实例化输入/输出两池并安排帧复制的所有权交接；`memory/frame_pool_address.v` 把六槽映射到当前工程的 DDR 字地址；`memory/ddr_read_burst_arbiter.v` 在发出读突发前要求客户端预留全部返回空间，再按突发所有者路由数据。`memory/ddr_write_drain_tracker.v` 按 Pango 写 ID 统计接受的写地址和 `axi_wready && axi_wusero_last` 完成事件，异常时锁住排空许可。`memory/capture_frame_admission.v` 在 VS 后留出 8 个 DDR 时钟的流水保护，再等待采集写事务排空后发布或中止帧；`memory/capture_pixel_gate.v` 在像素时钟域按整帧决定是否写入。采集池、写排空和整帧门控已接入独立 Stage 3 PDS 视频顶层并通过综合；处理输出池和复制引擎仍只在独立综合测试顶层，实板验证尚未进行。
- `correction/`：逆向坐标映射、坐标 FIFO、逐邻点边界判断、RGBX8888 双线性插值及 Stage 4 片上测试图闭环。独立 `stage4_algorithm_demo` 已完成 PDS 位流生成；真实 DDR Tile Cache 尚未接入该算法链。
- `control/`：标定参数、UART 包接收和帧边界更新。阶段 3–5 再接入。

当前 `video/hdmi_loop.v` 是阶段 1 的可综合顶层；它与厂商 HDMI 配置模块和 PG2L200H 配置 PLL 一起组成 PDS 工程。

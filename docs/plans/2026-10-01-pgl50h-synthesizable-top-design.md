# PGL50H 可综合算法系统顶层设计

## 目标

建立可在紫光同创 PGL50H 上综合的算法系统顶层 `mes50hp_top`，将已经验证的畸变矫正数据通路组合为一个可自动处理整帧图像的模块，并通过图片级 XSim 回归验证。

本阶段的顶层边界位于 FPGA 用户逻辑与厂商 DDR3/视频接口 IP 之间。DDR3 PHY、HDMI/摄像头物理引脚和时钟 IP 必须在拿到 MES50HP 官方例程后接入，不在本阶段猜测或伪造。

## 数据通路

`frame_start` 启动一帧后，顶层按输出图像的光栅顺序生成 `(dst_x, dst_y)`：

1. `distortion_core_optimized` 计算反向映射源坐标；
2. `pixel_fetch_engine` 通过逻辑 DDR 请求/响应接口读取四个相邻 RGB888 像素；
3. `bilinear_interp` 完成双线性插值；
4. 顶层输出 RGB888、`valid`、`sof` 和 `eol`；
5. 最后一个输出像素完成时产生单周期 `frame_done`。

顶层一次只启动一帧，`frame_busy=1` 时忽略新的 `frame_start`。输出端当前采用不可反压的流接口；下游在 `out_valid=1` 时必须接收数据。后续接入视频时钟域时，应在本接口后加入异步 FIFO。

## 时钟与复位

- 顶层输入时钟端口名为 `clk`，本阶段按 MES50HP 板载 50 MHz 系统时钟验证。
- 外部低有效复位 `reset_n` 异步拉低，在 `clk` 域内经两级寄存器同步释放。
- `frame_start` 和相机参数输入均属于 `clk` 域。

## 外部接口

- 帧控制：`frame_start`、`frame_busy`、`frame_done`。
- 相机参数：焦距、主点、逆焦距以及三项径向畸变系数，保持现有 Q 格式。
- 逻辑 DDR：请求有效/就绪、像素地址、响应有效/就绪、RGB888 响应数据。
- 输出流：RGB888、有效、帧首和行尾。

逻辑 DDR 地址仍采用“像素索引”而非字节地址；未来的 DDR 控制器适配层负责把它转换成 AXI/Native 接口地址和突发访问。

## 综合策略

`distortion_image_pipeline` 增加参数化核心选择，默认仍使用原基准核心以保持已有回归不变；`mes50hp_top` 显式选择已经单独验证过的 Q18 窄位宽 `distortion_core_optimized`，以降低 PGL50H 上的乘法器和寄存器压力。

## 验证标准

图片级 XSim 使用 256×192 彩色畸变输入图和与 Q18 优化核心位精确一致的黄金结果。Testbench 应检查：

- 顶层能从一次 `frame_start` 自动处理完整一帧；
- 每个 RGB888 输出与黄金 MEM 逐像素一致；
- `sof` 只出现在首像素，`eol` 出现在每行末尾；
- 输出像素数恰好为 256×192；
- DDR 请求地址不越界；
- `frame_done` 只在最后一个输出像素时产生。

仿真中间文件和日志存放在 `xsim.dir/mes50hp_top_image_256x192`，图片与 MEM 结果存放在 `result/sim_assets/mes50hp_top_image_256x192`。

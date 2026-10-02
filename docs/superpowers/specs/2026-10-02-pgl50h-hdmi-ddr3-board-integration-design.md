# PGL50H HDMI + DDR3 板级接入设计

## 目标

为 MES50HP / PGL50H 开发板建立可综合的物理顶层 `pgl50h_board_top`：HDMI RX 将 RGB888 视频写入 DDR3 帧缓存，现有 `mes50hp_top` 从该帧缓存随机读取四邻域像素完成畸变矫正，处理结果经 HDMI TX 输出。

## 范围与边界

- `mes50hp_top` 保持算法核角色，接口和图像处理 RTL 不因板级外设而改变。
- `pgl50h_board_top` 是唯一 PDS 物理顶层，拥有时钟、复位、HDMI、DDR3 与 I2C 管脚。
- HDMI 和 DDR3 端口、时钟频率、管脚、电平及时序约束以官方例程的 `.fdc` 和顶层 Verilog 为唯一依据。
- 首版使用编译期固定的畸变标定参数；运行时寄存器配置不在本轮实现范围。
- 首版仅实现一帧一帧的离线式读写流程；不承诺实时双缓冲吞吐率，直到实板验证完成。

## 官方参考工程

官方压缩包将解压为只读参考副本，不能直接作为当前工程的 PDS 顶层。

| 参考工程 | 用途 |
| --- | --- |
| `06_hdmi_loop` | HDMI RX/TX 管脚、MS7200/MS7210 初始化、视频时钟和 `.fdc` 参考 |
| `07_ddr3_test` | DDR3 控制器/PHY IP、校准接口、DDR3 `.fdc` 与最小读写参考 |
| `10_HDMI_DDR3_OV5640_test` | 相机→DDR3→HDMI TX 组合参考；复用 DDR3、帧缓存写通道、HDMI TX 和视频时序，不引入 OV5640 顶层端口 |

## 模块结构

```text
MS7200 HDMI RX
  └─ RGB888 输入视频流
       └─ 官方 `wr_buf` DDR3 写通道
            └─ DDR3 输入帧
                 └─ `distortion_ddr_read_adapter`
                 ├─ 向 mes50hp_top 提供 mem_req_ready / mem_rsp_*
                 └─ 将按像素寻址的四邻域请求转换为官方 DDR3 读请求
                      └─ mes50hp_top
                           └─ RGB888 矫正输出流
                                └─ 非连续流写入器
                                     └─ DDR3 输出帧
                                          └─ 固定时序连续读取/跨时钟域
                                               └─ MS7210 HDMI TX
```

## 文件职责

| 文件 | 职责 |
| --- | --- |
| `board_reference/mes50hp/*` | 官方工程的不可修改参考副本 |
| `rtl/board/mes50hp/pgl50h_board_top.sv` | 物理板级顶层；只连接官方外设模块、适配器和算法核 |
| `rtl/board/mes50hp/ddr3_frame_buffer_adapter.sv` | 在 `mes50hp_top` 逻辑像素读接口与官方 DDR3 控制器端口间转换协议 |
| `rtl/board/mes50hp/algorithm_frame_writer.sv` | 将允许停顿的算法 RGB888 输出按 24-bit 连续格式写入独立 DDR3 输出帧区 |
| `rtl/board/mes50hp/ddr3_frame_reader.sv` | 从固定输出帧区逐行突发读取，并跨到 HDMI 像素时钟域连续播放 |
| `rtl/board/mes50hp/board_video_control.sv` | 帧边界、读写角色、算法启动及输出选择控制 |
| `constraints/mes50hp/pgl50h_board_top.fdc` | 从官方 `.fdc` 合并得到的物理管脚与时钟约束；不得凭空指定管脚 |
| `sim/tb_pgl50h_board_top_compile.sv` | 不依赖物理 HDMI/DDR3 模型的顶层结构编译和接口连通性检查 |

## 帧与存储约定

- 输入帧写入 DDR3 的地址单位为 RGB888 像素，`mes50hp_top.mem_req_addr` 也保持像素单位。
- 读适配器负责把像素地址转换为官方 DDR3 控制器要求的字节地址或突发地址；该换算以官方 `fram_buf`/读控制模块的定义为准。
- 在输入帧写完且 DDR3 写通道空闲后，控制模块产生单个 `frame_start` 给 `mes50hp_top`。
- `mes50hp_top.frame_done` 后，输出视频通道只读取本次矫正输出帧；下一输入帧开始前不覆盖正在处理的输入帧。
- `mes50hp_top.out_valid` 允许停顿，必须先写完整输出帧；MS7210 只接收由输出帧缓存产生的连续像素流，不能直接连接算法输出。
- 首版完成一次输入帧捕获和矫正后持续循环显示该输出帧；需要更新画面时复位重新捕获，不实现实时多帧并行。
- 若坐标无效，现有算法输出黑色；板级控制不得自行改写此语义。

## 时钟与复位

- 50 MHz 板载时钟及其物理管脚由官方 `.fdc` 读取后确定。
- HDMI RX、DDR3 用户接口、算法核与 HDMI TX 是否同频由官方 PLL/IP 的真实端口决定；不同频域之间使用官方例程已有机制或新增明确的 CDC/FIFO 模块。
- 外部复位在各时钟域异步断言、同步释放。`mes50hp_top` 继续使用现有 `mes50hp_reset_sync`。

## 验证与验收

1. 解压后逐项核对官方顶层、`.fdc`、HDMI 初始化源与 DDR3 IP 生成文件是否齐全。
2. `tb_pgl50h_board_top_compile` 必须在缺少物理 HDMI/DDR3 行为模型时仍能完成结构 elaboration。
3. 原有 `tb_mes50hp_top_image.sv` 必须继续通过，证明算法核端口和行为未被板级接入破坏。
4. PDS 中以 `pgl50h_board_top` 为顶层后，编译、综合和 Device Map 不得再把逻辑 `mem_req_*`、标定参数等内部端口算作 FPGA 物理 IO。
5. 首次实板验证顺序为：时钟/复位 → HDMI loop → DDR3 校准与读写 → 输入帧缓存 → 算法读回 → HDMI 矫正输出。

## 兼容性约束

- 官方例程标明基于 PDS 2022.1；当前工程使用的 PDS 版本若不同，DDR3/PLL IP 必须优先在当前安装版本中重新生成，不能仅复制旧版本生成目录后假定可用。
- 参考工程中的厂商生成文件、管脚和电气属性必须原样核对后再导入；算法 RTL 不得直接依赖参考工程的相对路径。
- `fram_buf.v` 的读通道是固定视频时序的连续突发读，不能直接满足畸变矫正的随机四邻域读；本项目仅复用其写通道依赖和 AXI 控制结构，并新增随机读适配器。

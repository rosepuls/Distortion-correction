# 视频处理接口规范

## 1. 目的

本文档冻结无板卡阶段所有算法模块使用的基础接口语义，避免各模块分别定义时序、颜色顺序和同步信号。

本规范适用于：

- RGB 转灰度；
- 亮度和增益；
- Gamma LUT；
- 3×3 Window Generator；
- Gaussian、Sobel 和 Morphology；
- 畸变坐标生成；
- 双线性插值；
- 行为级 Pixel Fetch。

真实 HDMI、DDR3 和厂商总线由板级适配层连接，不直接进入算法核心。

---

## 2. 全局约定

| 项目 | 第一版约定 |
|---|---|
| 主目标分辨率 | 1280×720 |
| 主目标帧率 | 60 fps |
| RGB 数据格式 | RGB888 |
| RGB 打包顺序 | `{R[7:0], G[7:0], B[7:0]}` |
| 灰度格式 | unsigned 8 bit |
| 像素坐标原点 | 左上角 `(0,0)` |
| x 方向 | 向右递增 |
| y 方向 | 向下递增 |
| 行扫描顺序 | 从左到右 |
| 帧扫描顺序 | 从上到下 |
| 复位名称 | `rst_n` |
| 复位极性 | 低有效 |

Python 使用 OpenCV 读取彩色图像时必须显式执行 BGR → RGB 转换，不能把 OpenCV 默认的 BGR 顺序直接当作 RTL 输入。

---

## 3. 基础像素流接口

### 3.1 输入端口

| 信号 | 方向 | 位宽 | 含义 |
|---|---:|---:|---|
| `clk` | input | 1 | 像素处理时钟 |
| `rst_n` | input | 1 | 低有效复位 |
| `in_pixel` | input | `IN_PIXEL_WIDTH` | 输入像素数据 |
| `in_valid` | input | 1 | 本周期输入像素有效 |
| `in_sof` | input | 1 | 本周期是每帧第一个有效像素 |
| `in_eol` | input | 1 | 本周期是当前行最后一个有效像素 |

### 3.2 输出端口

| 信号 | 方向 | 位宽 | 含义 |
|---|---:|---:|---|
| `out_pixel` | output | `OUT_PIXEL_WIDTH` | 输出像素数据 |
| `out_valid` | output | 1 | 本周期输出像素有效 |
| `out_sof` | output | 1 | 本周期是每帧第一个有效输出像素 |
| `out_eol` | output | 1 | 本周期是当前输出行最后一个有效像素 |

### 3.3 握手与流控

基础算法链不提供 `ready`，采用无反压流接口：

- `in_valid=1` 表示模块必须在该时钟沿接收输入；
- `in_valid=0` 表示空拍，坐标、窗口和有效像素计数不得前进；
- 模块不能要求上游 HDMI 像素流暂停；
- 固定流水模块必须能够在稳态下实现 1 Pixel / Clock；
- `out_valid` 只在输出像素有效时置 1；
- `out_sof` 和 `out_eol` 仅在 `out_valid=1` 时有意义。

### 3.4 帧和行语义

- `in_sof` 与一帧中坐标 `(0,0)` 的像素同周期出现；
- `in_eol` 与坐标 `(IMAGE_WIDTH-1,y)` 的像素同周期出现；
- 第一行也必须正常产生 `in_eol`；
- 每帧只有一个有效的 `in_sof`；
- 不单独提供 `sol`，新行由上一有效行的 `eol` 推导；
- 模块内部的 x/y 计数器只在 `in_valid=1` 时更新；
- 收到 `in_sof=1 && in_valid=1` 时，内部坐标和帧状态重新对齐到 `(0,0)`。

### 3.5 控制信号延迟

像素和控制信号必须经历相同的有效流水延迟：

```text
in_pixel ───────────────► out_pixel
in_valid ── 同步延迟 ──► out_valid
in_sof   ── 同步延迟 ──► out_sof
in_eol   ── 同步延迟 ──► out_eol
```

每个 RTL 模块必须在模块头注释和 `numeric_spec.md` 中记录固定延迟 `LATENCY`。修改流水级后必须同步修改 Testbench 期望延迟。

畸变基准路径的已实现延迟为：`coordinate_gen` 1 拍，`distortion_core` 5 拍，级联共 6 拍。`distortion_core` 的输入端口为 `in_u/in_v/in_valid/in_sof/in_eol`，输出端口为 `out_src_x_q19/out_src_y_q19/out_x0/out_y0/out_dx_q16/out_dy_q16/out_coord_valid/out_valid/out_sof/out_eol`；所有输出控制信号与坐标结果严格同拍。

---

## 4. 参数化要求

流式模块优先使用以下参数：

```systemverilog
parameter int IMAGE_WIDTH     = 1280;
parameter int IMAGE_HEIGHT    = 720;
parameter int IN_PIXEL_WIDTH  = 8;
parameter int OUT_PIXEL_WIDTH = 8;
```

要求：

- 图像宽高不能散落为未命名常数；
- Testbench 可以用较小图像，例如 8×6，加快边界验证；
- 位宽变化不能破坏 `valid/sof/eol` 语义；
- 720P 参数用于最终回归，而不是所有单元测试都强制使用整帧数据。

---

## 5. 复位行为

复位期间：

- `out_valid=0`；
- `out_sof=0`；
- `out_eol=0`；
- 坐标、窗口状态和流水有效位清零；
- 数据输出值不作为功能判定依据，但建议置 0 便于观察波形。

解除复位后，模块等待第一个有效 `in_sof` 建立帧同步。复位后但收到 `in_sof` 前的数据在正式系统中不应出现；Testbench 可以注入这类数据验证模块不会错误产生帧首标记。

---

## 6. 配置参数接口

亮度、增益、Gamma、阈值和畸变系数第一版使用普通配置端口或寄存器输入。

统一规则：

- 参数只允许在帧间更新；
- 上层必须在下一帧 `sof` 到达前保持新参数稳定；
- 模块在 `in_sof && in_valid` 时锁存一帧所需参数；
- 同一帧内不允许参数变化导致前后像素采用不同配置。

后续若增加寄存器总线，只替换配置适配层，不改变算法数据通路。

---

## 7. Pixel Fetch 请求/响应接口

Pixel Fetch 与 DDR 行为模型存在可变延迟，因此采用独立握手接口。

### 7.1 请求通道

| 信号 | 方向 | 含义 |
|---|---:|---|
| `req_valid` | master → memory | 请求有效 |
| `req_ready` | memory → master | 本周期可以接收请求 |
| `req_addr` | master → memory | 逻辑像素地址 |

请求在以下条件成立的时钟沿被接受：

```text
req_valid && req_ready
```

第一版 `req_addr` 表示线性像素编号，而不是厂商 DDR 字节地址：

```text
req_addr = y × FRAME_STRIDE_PIXELS + x
```

这样可以把 RGB888 的物理打包、DDR 数据宽度和突发规则隔离到板级存储适配器中。

### 7.2 响应通道

| 信号 | 方向 | 含义 |
|---|---:|---|
| `rsp_valid` | memory → master | 返回像素有效 |
| `rsp_ready` | master → memory | 本周期可以接收返回像素 |
| `rsp_data` | memory → master | 返回 RGB888 像素 |

响应在以下条件成立的时钟沿被接受：

```text
rsp_valid && rsp_ready
```

第一版行为模型规定响应顺序与请求接受顺序一致。以后若允许乱序返回，必须增加事务标签，不能依赖隐含顺序。

### 7.3 视频连续性要求

真实输出视频不能等待 DDR，因此可变延迟接口不能直接连接 HDMI 输出。最终系统需要至少一种机制：

- Local Pixel Cache；
- 请求预取；
- 输出 FIFO；
- Tile 调度；
- 可证明满足吞吐的组合方案。

无板卡阶段只定义接口并建立可控延迟的行为模型，不假设 DDR 每周期都能返回数据。

---

## 8. 模块接口检查表

新增模块前必须回答：

- [ ] 输入和输出像素格式是什么？
- [ ] 模块固定延迟是多少？
- [ ] 是否达到稳态 1 Pixel / Clock？
- [ ] 空拍时内部状态是否保持正确？
- [ ] `sof/eol/valid` 是否与数据对齐？
- [ ] 参数是否在帧首锁存？
- [ ] 复位后何时重新建立帧同步？
- [ ] 是否依赖任何厂商专用接口或原语？

只有上述项目均明确后，模块才进入 RTL 编写阶段。

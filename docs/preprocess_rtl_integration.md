# 预处理 RTL 集成说明

## 1. 模块连接

第一轮灰度检测链按下列顺序连接：

```text
RGB888
  -> rgb2gray
  -> brightness_gain（可旁路）
  -> gamma_lut（可旁路）
  -> line_buffer_3x3
  -> window_3x3
  -> gaussian_3x3
  -> sobel_3x3
  -> threshold
  -> line_buffer_3x3 + window_3x3（针对二值流的第二实例）
  -> morphology
```

`line_buffer_3x3` 与 `window_3x3` 是配对模块。前者把每个输入像素转换为同列的 `tap_top/tap_middle/tap_bottom`，后者将三行 tap 展开为 `p00` 至 `p22`。两个模块的 `IMAGE_WIDTH`、`IMAGE_HEIGHT` 和 `PIXEL_WIDTH` 参数必须一致。

`gaussian_3x3`、`sobel_3x3` 和 `morphology` 均直接使用窗口的九个输出。若同一时刻需要并行的 Gaussian、Sobel 分支，可以共享同一份灰度窗口；形态学处理的是阈值后的二值数据，必须使用自己的 1-bit 行缓存与窗口实例。

## 2. 完整零填充时序

3×3 窗口遵循 `border_policy.md`：每个真实图像坐标都有一个输出窗口，图像外像素为 0。因此：

- 顶边由行缓存对缺失的前两行输出 0；
- 左边由窗口水平移位寄存器的初值补 0；
- 右边窗口在下一输入行的第一个像素期间输出；
- 帧尾由行缓存自动生成两条 `out_synthetic=1` 的全零行，分别产生底边窗口和释放最后一个右边窗口。

源视频在最后一个真实 `in_eol` 后，必须提供至少 `2 × IMAGE_WIDTH` 个时钟周期的垂直消隐时间，直到下一帧 `in_sof`。720p HDMI 的垂直消隐通常远大于这个值；若未来输入格式不能满足，应改成显式 `frame_flush` 控制或使用带反压的帧缓存结构。

## 3. 延迟与吞吐

除窗口基础设施外，`rgb2gray`、`brightness_gain`、`gamma_lut`、`bilinear_interp`、`gaussian_3x3`、`sobel_3x3`、`threshold` 和 `morphology` 都是单寄存器输出模块，稳态吞吐为 1 Pixel/Clock。

`line_buffer_3x3` 使用同步读 DRM 风格行 RAM，内部为两级寄存器路径；相对一次输入采样，`tap_*`/`out_*` 在下一时钟周期有效。`valid/sof/eol/synthetic` 与三路 tap 同拍对齐，稳态吞吐仍为 1 Pixel/Clock。`window_3x3` 在收到第一行之后，于下一行第 2 个有效 tap（逻辑坐标 `(1,1)`）产出中心为 `(0,0)` 的第一窗口；随后按光栅顺序产出所有 `W × H` 个窗口。每条输出行的最后一个像素会在下一条输入行的第一个 tap 期间出现，但不会改变输出坐标或 `out_eol` 语义。

## 4. 配置规则

- `brightness_gain`：`cfg_gain` 为 unsigned Q4.12，`cfg_offset` 为 signed 10-bit 整数；在 `sof` 锁存。
- `gamma_lut`：双 bank 256×8 LUT；软件向未激活 bank 写满 256 项，再在帧间切换 bank；`cfg_enable` 和 bank 选择在 `sof` 锁存。
- `threshold` 与 `morphology`：阈值、膨胀/腐蚀选择在 `sof` 锁存。
- `bilinear_interp`：每个通道独立执行 Q0.16 双线性插值，`coord_valid=0` 时输出黑色。

所有配置都必须在一帧开始前稳定，不能在有效帧中修改。

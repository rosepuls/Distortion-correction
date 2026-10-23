# Stage 6：120° 广角镜头 Brown-Conrady 视觉试值

_2026-10-22；PG2L200H；工程 `fpga/project/stage6_radial_ddr/`。_

## 当前映射

前一版 `k1=+0.25` 的纯径向正向位移让用户实拍中的屏幕边线仍明显弯曲，且主要变化集中在外围。当前工程改为桶形矫正方向的固定输出到源坐标映射，并加入两个切向项：

```text
x = (u-640)/512, y = (v-360)/512, r2 = x*x+y*y
k1 = -0.25, k2 = +0.0625, p1 = +0.03125, p2 = -0.03125
source_x = 640 + 512 * [x*(1+k1*r2+k2*r2*r2) + 2*p1*x*y + p2*(r2+2*x*x)]
source_y = 360 + 512 * [y*(1+k1*r2+k2*r2*r2) + p1*(r2+2*y*y) + 2*p2*x*y]
```

源坐标按有符号 Q16.16 运算，再从 DDR 图块缓存双线性取样。光学中心 `(640,360)` 按模型固定，但邻近位置仍逐像素重映射；外围向内取源，输出直线有明显变化。这里的 512 是视觉测试用的归一化尺度，四个系数也未经过相机标定。仅凭 120° 视场角无法确定真实内参和畸变系数。

映射实现为 [`stage6_brown_mapper.sv`](../../fpga/rtl/correction/stage6_brown_mapper.sv)，复制到本工程原 `demo_radial_mapper.sv` 路径以兼容已有 PDS 工程。正常工程与帧率诊断工程使用相同文件内容和系数。`RADIAL_DENOM_SHIFT` 为遗留兼容参数，此版不用于计算。

## 验证

- [`Run-Stage6RadialPipeline.ps1`](../../fpga/sim/Run-Stage6RadialPipeline.ps1)：Vivado 2020.2 定向仿真通过，核对中心、非中心及四角源坐标，真实 DDR 图块取样和输出元数据顺序。
- PDS 2022.2-SP6.4 全流程通过，后布局报告 `All Constraints Met`。DDR 125 MHz 时钟域建立裕量 +0.524 ns；输出 74.2501 MHz 像素域建立裕量 +8.278 ns。位流 9,188,552 字节，SHA-256 `0338BB4EA7F5C98EBE5EC3BF8A2B9DE9589888AB25AA715D90F3B2921195E725`。
- 实板画面和实际处理帧率：待烧录测试。请与此前 `k1=+0.25` 画面在同一相机角度、同一屏幕直线下比较，并记录 LED 状态。

普通显示位流为[本工程 `.sbit`](../../fpga/project/stage6_radial_ddr/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit)。测帧率请用[配套诊断工程](stage6-radial-fps-diagnostic.md)的 `.sbit` 和 `.fic`。

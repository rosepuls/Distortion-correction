# 盘古200Pro+ / PG2L200H 资源与存储边界

活动目标板为盘古200Pro+，器件为 `PG2L200H-6FBB676`（Logos2）。板载存储为两片 512 MB DDR3，组成 x32 通道；本项目沿用 256-bit AXI 用户数据通路和 RGBX8888 输入帧、RGB888 输出帧布局。

DDR3 PHY、PLL 和 DRM 必须来自 `PDS 2022.2-SP6.4` 的 PG2L200H IP。旧 Logos/PGL 系列 IP 不属于该工程的可用依赖。

# Distortion-correction

面向紫光同创盘古50 MES50HP（PGL50H-6IFBG484）的实时视频畸变矫正与轻量视觉处理项目。

当前处于无板卡、无 PDS 阶段，主要使用 Python 建立参考模型，并使用 Vivado Simulator 验证可迁移的 Verilog/SystemVerilog 核心模块。最终板级工程使用 Pango Design Suite（PDS），板卡专用的时钟、HDMI、DDR3、CDC 和引脚约束与算法核心隔离。

当前工作顺序：

```text
接口、数值与边界规范
        ↓
Float Golden Model
        ↓
Bit-accurate Integer Model
        ↓
RTL 与自动 Testbench
        ↓
整链仿真及存储访问预研
```

规范文件位于 [`docs/`](docs/)；RTL、软件模型和仿真文件将按计划逐步加入对应目录。

项目计划：

- [MES50HP 总体项目计划](docs/plans/mes50hp_project_plan.md)
- [无板卡阶段推进计划](docs/plans/boardless_development_plan.md)

仿真操作：

- [Vivado XSim / Codex 仿真 SOP](docs/xsim_codex_sop.md)

板卡资料：

- [MES50HP 资源与存储说明](docs/board/mes50hp_resources.md)
- [MES50HP 时钟与 CDC 规划](docs/board/mes50hp_clock_plan.md)
- [MES50HP 接口与引脚资料索引](docs/board/mes50hp_pin_map.md)

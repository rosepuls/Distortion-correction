# Distortion-correction

面向紫光同创盘古200Pro+（`PG2L200H-6FBB676` / Logos2）的实时视频畸变矫正与轻量视觉处理项目。

算法、缓存、黄金模型与 XSim 回归保持板卡无关；活动板级工程位于 `rtl/board/pg2l200h/`、`rtl/vendor/pg2l200h/`、`ip/pango/pg2l200h/` 与 `boards/pg2l200h/`。板级实现使用 Pango Design Suite 2022.2-SP6.4，专用时钟、HDMI、DDR3、CDC 和引脚约束与算法核心隔离。

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

- [原始项目计划（历史记录）](docs/plans/基于紫光同创盘古200Pro+%20盘古200Pro+（PG2L200H）的视频畸变矫正与轻量视觉处理系统项目计划.md)
- [无板卡阶段推进计划（历史记录）](docs/plans/无板卡阶段临时推进计划.md)

仿真操作：

- [PG2L200H 结构编译](sim/run_pg2l200h_board_top_compile.ps1)
- [PG2L200H 迁移资产检查](sim/check_pg2l200h_migration.ps1)

板卡资料：

- [PG2L200H 资源与存储说明](docs/board/pg2l200h_resources.md)
- [PG2L200H 时钟与 CDC 规划](docs/board/pg2l200h_clock_plan.md)
- [PG2L200H 接口与引脚资料索引](docs/board/pg2l200h_pin_map.md)
- [PG2L200H PDS 交接](docs/board/pg2l200h_pds_handoff.md)

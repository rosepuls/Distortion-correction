# PG2L200H（盘古200Pro+）板卡工程

目标器件为 `PG2L200H-6FBB676`，架构为 Logos2。PDS 顶层为 `rtl/board/pg2l200h/pg2l200h_board_top.sv`。

`constraints/` 以官方 200Pro+ HDMI+DDR3 例程为基线；`pds/` 保存可追溯的工程定义和实现入口，不提交 PDS 的生成数据库与日志。
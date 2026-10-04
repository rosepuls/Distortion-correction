# PGL50H 板卡工程

本目录仅保存 PGL50H/MES50HP 专属的工程资料：

- `constraints/`：实际顶层使用的 `.fdc` 约束；
- `pds/pgl50h_rtl_synth/`：PDS 工程、实现报告和该板卡构建产物。

PDS 顶层为 `rtl/board/pgl50h/pgl50h_board_top.sv`。工程打开后应从该目录中的 `.pds` 文件启动，不能再使用旧的根目录 `pds/`。

新增其他板卡时复制本目录结构到 `boards/<new-board>/`，但不要复制 PGL50H 的引脚约束或 DDR IP 参数。

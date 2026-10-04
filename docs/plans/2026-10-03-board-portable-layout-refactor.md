# 面向可换板卡的目录重构计划

## 目标

将可复用的图像算法、与器件无关的平台逻辑，以及 PGL50H 专属逻辑分离。新增一块板卡时，应只新增对应的 `board`、`vendor`、`boards` 子树和实现相同平台接口的适配器，不应改动算法 RTL。

## 目标目录

```text
rtl/
  algorithm/
    distortion/
    interpolation/
    preprocess/
    detect/
  platform/common/
    memory/
  board/pgl50h/
  vendor/pgl50h/
boards/pgl50h/
  constraints/
  pds/pgl50h_rtl_synth/
```

`ip/pango/` 暂时保持原位：其中是 Pango 工具生成的 IP，避免为了目录美观而破坏其内部相对路径。后续新增板卡应在各自 `boards/<board>/` 下维护 PDS、约束和 IP 生成说明。

## 迁移规则

1. 只移动文件，不改动任何 RTL 模块名、端口或时序逻辑。
2. 所有可执行仿真脚本、PDS 工程、约束引用和当前使用说明必须同步更新。
3. 历史设计记录保留原始路径，以保持决策可追溯；新建的目录说明提供当前路径映射。
4. 以 `sim/check_project_layout.ps1` 作为目录契约，再运行板级编译仿真和代表性算法仿真，证明重构没有改变功能。

## 迁移后新增板卡的最小工作量

1. 复制 `boards/pgl50h/` 的工程组织方式，建立 `boards/<new-board>/`。
2. 新增 `rtl/board/<new-board>/`：物理顶层、时钟复位、输入输出和 DDR 适配。
3. 新增 `rtl/vendor/<new-board>/`：只放供应商例程或该板专用 IP 封装。
4. 保持 `rtl/algorithm/` 与 `rtl/platform/common/` 不变，通过相同的像素/帧缓存接口接入。

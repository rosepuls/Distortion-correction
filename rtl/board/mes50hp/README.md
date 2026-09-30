# MES50HP 板卡层

本目录仅存放MES50HP/PGL50H专用RTL。计划模块：

```text
mes50hp_top.sv
clock_reset.sv
i2c_master.sv
ms7200_init.sv
ms7200_rx_if.sv
ms7210_init.sv
ms7210_tx_if.sv
video_cdc.sv
ddr3_frame_buffer.sv
```

算法模块不得反向依赖本目录。

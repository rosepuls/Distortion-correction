# Stage 10 模式预取与取样、插值重叠工程

本独立工程由窗口复用版复制，唯一 RTL 差异为 `source/rtl/correction/adaptive_sampler.sv`，内容与 `sim/throughput_overlap_dual/adaptive_sampler.sv` 一致。仿真测试结果见后者目录中的 README。生成目录不继承旧构建产物。

应用户要求不生成新 FIC；本工程移除了调试核插入配置。其位流不提供旧版 Fabric Debugger 探针，不可使用窗口复用版 FIC 作为本次构建的配套文件。运行 `Build-Overlap.ps1` 生成位流并记录输入哈希及最终时序；须以 `overlap-build.json`、新报告和用户实际板测为准。

2026-11-02 已生成 `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`，SHA-256 为 `910778902BED5A804F125C89681CA7CE67380B170938F5F0E911CAC005949B7B`；125 MHz `ddrphy_sysclk` 布线后最差 setup WNS -0.315 ns，TNS -9.387 ns，共 92 个违例端点。该构建未通过时序，位流仅供实验，尚未上板验证；构建脚本因此返回失败并将 manifest 标记为 `timing_failed`。本工程未生成 FIC。

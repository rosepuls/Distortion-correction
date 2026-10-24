# PDS 工程

`New-Stage1Project.ps1` 从本机厂商例程生成 HDMI 直通工作工程。`stage1_hdmi_loop/` 是可重新生成的本地目录，不提交厂商源码和 IP。

阶段 2 以 PG2L200H 的 `4_10_timing/4_10_HDMI_IN_DDR3_HDMI_OUT` 为基线，在阶段 1 硬件验收后建立独立工作工程；不要复用阶段 1 的 PLL 或直接套用 1080p 时序。阶段 2 接收端也需要沿用 `fpga/edid/720p60.hex`，否则电脑可能重新选择 1080p 活动信号。

`New-Stage5IdentityProject.ps1` 从 Stage 3 CDC 修复工程复制独立的 `stage5_identity_ddr/`，把处理侧帧复制替换成单位映射、DDR Tile Cache 与流水双线性插值。`Run-Stage5IdentityProject.ps1` 只有在 PDS 全流程结束且时序报告显示 `All Constraints Met` 时才报告通过。板测前先读 `docs/results/stage5-identity-ddr.md`。

`New-Stage6RadialProject.ps1` 在相同 DDR 处理架构中接入固定 Brown-Conrady 广角试值，生成独立 `stage6_radial_ddr/` 工程。当前 `k1/k2/p1/p2` 已同时用于普通工程和配套帧率诊断工程；位流与上板预期见 `docs/results/stage6-radial-ddr.md`。系数尚未来自相机标定。

`New-Stage5FpsDiagnosticProject.ps1` 可从任意兼容的 DDR 帧处理工程生成配套帧率诊断副本。Stage 6 Brown-Conrady 诊断工程位于 `stage6_radial_fps_debug/`；帧率测试说明见 `docs/results/stage6-radial-fps-diagnostic.md`。

Stage 6 径向帧率诊断可用 `New-Stage6RadialFpsDiagnostic.ps1` 生成、`Run-Stage6RadialFpsDiagnostic.ps1` 构建；必须将该工程同次构建的 `.sbit` 与 `.fic` 配对。

Stage 7 写入重叠的实板处理帧率约为 59.43 fps，输入完整发布在 60 秒窗口比原始 VSYNC 少 37 帧。入口定位诊断位流位于 `stage7_write_overlap_ingress_diag_16x8/`；它记录拒收、中止、采集写排空和采集槽等待。构建结果、SHA-256 和完整 Fabric Debugger 通道表见该目录下的 `README.md` 与 `README_JTAG.md`。

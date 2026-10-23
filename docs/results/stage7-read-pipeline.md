# Stage 7 16×8 DDR 行读取并发实验

## 依据

Stage 8 读等待诊断的实板快照相隔 61 秒：处理完成帧增加 1,873，约 30.70 fps；最近完成帧为 4,009,751 个 125 MHz 周期。该帧 14,345 次缓存未命中，缓存填充 2,662,452 周期；读首拍等待 1,672,256 周期，仲裁等待 327,398 周期，DDR `ARREADY` 等待 61 周期，拍间等待为 0。由此选择先把同一 tile 的四行读取重叠。

## 候选结构

独立工程：`fpga/project/stage7_read_pipeline_16x8/`。

- 保留 16×8 tile 缓存、固定坐标映射、帧槽逻辑和 Stage 8 四类等待计数。
- 适配器为一个 tile 连续提交四个 4-beat 行突发，使用 transform AXI ID 1；AXI 同 ID 响应按请求顺序归还。
- 适配器预留并缓存完整 16-beat tile，再依次写入原缓存接口。显示读保留 AXI ID 0 和单笔在途限制。
- 缓存一次请求后连续接收四行；每行结束仍保持在数据接收状态，直到整块写完才置有效。
- 读仲裁器允许 transform 端最多 4 笔行突发未完成，同时保留显示读仲裁。
- 候选 FIC 已修正 Stage 8 诊断位流遗留的旧总线名称。

## 构建状态

- PDS 2022.2-SP6.4 重新综合、布局布线并生成修复版位流。
- 时序报告：`Design Summary : All Constraints Met`；`ddrphy_sysclk` 125 MHz WNS 为 +0.146 ns。
- 位流：`fpga/project/stage7_read_pipeline_16x8/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`  
  SHA-256：`1C76E121F392B1F459793E005C614E99E344DABCDCA298CDEA26E20119509913`
- 配套 FIC：`fpga/project/stage7_read_pipeline_16x8/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.fic`  
  SHA-256：`5B23FB04EDDE0D435EFFF8F421A82E67FFFB172034F2B1F59215FFED958DD869`

## 首版实板故障与修复

首版位流 SHA-256 `726B8F73E43FFBEB146807D084AD37B0C516997075230F6C872D4B6681F4E771` 上板后，用户观察到 LED5/6/7 不亮、LED4 亮、屏幕黑。该版**不可再用于性能测试**。

根因是整块填充握手不匹配：新适配器一次请求便接收和输出四行，缓存却在第一行的第四拍后返回 `FILL_REQ`。适配器停在 `OUTPUT` 等待缓存接收第二行，缓存停在 `FILL_REQ` 等待适配器接受下一次请求，双方互等。针对真实缓存与适配器的 Vivado 仿真复现为 `rows=1 cache_state=1 adapter_state=2`。修复后四行全部完成，查找请求返回了预期行数据；四笔 transform 读突发与显示读并发的仲裁仿真也通过，响应错误计数为 0。

## 修复版上板采样

修复版尚待实板验证。请用上面的**新 `.sbit`** 和同目录 `.fic`，保持与前次相同的动态 720p 输入。先确认有画面、LED6/7 状态恢复且错误标志为零，再间隔约 60 秒采两次 Listing，比较处理完成 fps、帧周期、缓存填充周期、首拍等待和仲裁等待。

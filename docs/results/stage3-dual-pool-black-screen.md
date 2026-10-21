# Stage 3 双帧池候选版黑屏定位

## 实板观察

- 候选位流 SHA-256：`34A3553698AEEFA91A9B4F61311767BEEA7210F825E76FBA2C002DF06B414CB8`。
- 用户反馈：LED0 闪烁，其余灯常亮；显示器识别到信号，但画面始终黑色。LED4–LED7 是上电后逐渐亮起的，未曾短暂出现正常画面。
- 首次诊断位流上板后，用户更正的灯态为 LED0 闪烁、LED1–3 常亮、LED4–7 全暗。LED1 是 DDR 初始化，LED2 是 HDMI 输入初始化，LED3 是 HDMI 输出初始化；初始化正常，但首次诊断版没有获得输出帧。此灯态不能用于判定显示读错误。
- 原版 LED4/5/6/7 分别锁存原始 DE、门控像素、输入完整帧发布、输出池显示槽有效。这证明链路至少推进到输出槽取得，不证明 DDR 显示读或 RGB 数据正确。

## 当前故障边界

原候选版 `fram_buf.v` 的 `display_pipe_ok` 同时要求 `display_valid`、无 `display_frame_blocked`、`display_read_error_count == 0` 和 `read_arbiter_error_count == 0`。`rd_buf.v` 在该信号为低时把 RGB 输出强制为零。`display_read_error_count` 只在 DDR 复位时清零；因此一次欠读就使输出永久黑屏，即使适配器在后续 VS 已清除帧级阻断。这是已确定的持续黑屏原因。

首次去除累计错误门控后，实板能显示画面，但 LED6 和画面同步快速闪烁。用户提供的两张照片中，一张画面完整，另一张只有顶部一部分有图像、其余区域黑屏。这符合某行检测到缓冲距离异常后，适配器阻断该帧余下画面，并在下一次输出 VS 恢复的行为。LED5 灭表明读仲裁器未记录错误。实板上的具体 DDR 等待时间尚未测量。

## 独立诊断位流

- 工程：`fpga/project/stage3_dual_pool_copy_black_diag`，从已验收稳定工程用同一生成脚本创建。首次生成时，脚本错误地用公共 `capture_pixel_gate.v` 覆盖了已验收版门控文件；公共版本额外要求 `!vs_in`，而原候选版没有这一条件。首次诊断位流因此不是与候选版相同的视频路径，已废弃。脚本已改为保留基线门控文件，诊断工程也已恢复为与原候选版逐字相同的门控文件。修正后的功能 RTL 除 LED 映射外，与候选版相同；`fram_buf.v` 另有声明顺序差异，`rd_buf.v` 仅行尾格式不同。
- 诊断位流：`fpga/project/stage3_dual_pool_copy_black_diag/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`。
- 曾生成门控修正诊断位流 SHA-256 `7E69305DB06C49043C5263F4B53C5B0344604BDB405CCB47DFF51536FCD61698`。旧哈希 `5F3911588CEE485446B785BAABC717923A39293540013E7C72FA87CF4D390829` 对应错误门控版本，已废弃。诊断工程目录中的位流后来已被下一版覆盖，不能仅凭路径套用此版的 LED 映射。
- 这版曾完成 PDS 全流程，受约束路径 `All Constraints Met`，DDR 125 MHz 域慢角建立余量 +0.834 ns。

以下表格对应后来覆盖诊断工程位流的 `CCFB…` 版本：

| 灯 | 诊断含义 | 性质 |
| --- | --- | --- |
| LED4 | 消费/写回指针计算出的缓冲距离异常，原标记为欠读；也可能由错误的跨域指针触发 | 锁存至 DDR 复位 |
| LED5 | 输出 VS 到来时显示行或 DDR 突发仍在途 | 锁存至 DDR 复位 |
| LED6 | DDR 返回末拍/响应异常，或行请求长度为零 | 锁存至 DDR 复位 |
| LED7 | 输出 DE 有效期间曾出现非零 RGB 像素 | 锁存至 DDR 复位 |

先前对 LED 状态的记录在位流版本切换期间被混淆，不能据此推断读仲裁器错误计数为 0。以下采用用户明确确认的 `CCFB…` 位流哈希和灯态。

原因细分诊断位流：`fpga/project/stage3_dual_pool_copy_black_diag/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`，SHA-256 `CCFB3405039EF6B37DEBD5DC54DFE237DDEA5BDD319A32ACA01D966C27963846`，大小 9,188,552 字节。PDS 完成 Compile、Synthesize、Device Map、Place & Route、Report Timing、Generate Bitstream；受约束路径 `All Constraints Met`，DDR 域慢角建立余量 +0.868 ns。用户确认本次烧录的正是此最新位流，报告 LED5、LED6 不亮，其余正常；按本版映射，LED4 欠读标志和 LED7 非零 RGB 标志亮，LED5 帧边界忙标志和 LED6 返回协议/零长度行标志灭。

这将故障边界收窄到显示读适配器的缓冲距离检查：`display_read_adapter.v` 根据跨域消费指针计算出的占用量及已预留返回量超过 512 时，置位 `fault_flags[0]`，并阻止当前帧继续供数。此前把此信号直接解释为实际欠读并不充分，因为不正确的跨域指针同样能触发该检查，后续已复现这种误报。LED7 仅表示 DE 有效期间曾有至少一个非零 RGB 像素，不代表完整帧。LED5/6 灭表明适配器没有记录帧边界在途、DDR 返回末拍/响应异常和零长度行；此版没有把读仲裁器错误计数映射到 LED。

## 帧级恢复与预取修复

- 新工程：`fpga/project/stage3_dual_pool_copy_recovery`。生成模板和此工程将 `display_pipe_ok` 中的累计 `display_read_error_count == 0` 条件删除，保留 `display_frame_blocked` 的帧级阻断及读仲裁器错误门控。累计错误计数仍供诊断使用。原候选工程与已验收的 `stage3_frame_pool_gate_fix` 保留。
- 第一版恢复位流 SHA-256 `3EF6458DD34A34DC0884B4D6CAE8E198561E1D5FBD6F6B4F88B9DA3215601250`，9,188,552 字节；PDS 全流程完成，受约束路径 `All Constraints Met`，DDR 125 MHz 域慢角建立余量 +0.933 ns。用户实板反馈 LED6 快速闪烁、LED5 灭，画面随 LED6 闪烁，并提供上述部分黑屏照片。因此此版未通过画面稳定性验收。
- 进一步检查发现 `rd_buf.v` 原来只在输出 VS 和每行 DE 上升沿请求一行；虽然物理读缓存有 512 个 256 位 beat，可容纳 3 条完整 720p 行及少量余量，但请求策略通常只提前约一行。一次较长 DDR 仲裁等待就可能用尽前沿数据。恢复工程现改为在显示读适配器有空且未读完当前帧时继续请求下一行，由适配器按物理缓冲剩余空间限制突发；行地址只在完整 160 beat 返回后推进，输出 VS 时重置行地址，DDR 复位后等待首次输出 VS 再发起预取。生成脚本也已同步此逻辑。
- 既有定向仿真 `Run-DisplayReadAdapter.ps1` 证实欠读后的下一个 VS 可清除帧级阻断，累计错误计数仍为 1。`Run-DisplayReadTiming.ps1` 使用 1280 有效像素、370 像素消隐、连续两帧各 12 行的合成模型，平常首突发等待约 6 µs，并对后续一行注入约 30 µs 等待。原按 DE 请求的读路径在此模型中发生欠读；连续预取版跨过 Gray 计数器回绕和帧重置，未发生欠读。此仿真说明预取深度有作用，不能单凭模型认定实板的 DDR 等待时间或保证实板已修复。
- 连续预取位流：`fpga/project/stage3_dual_pool_copy_recovery/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`，9,188,552 字节，SHA-256 `88CA1504B104AAA9A3557FED42D1E4BDBB6904CC1CB1C20C0D11B27BF021A6E9`。PDS 全流程成功，受约束路径 `All Constraints Met`，DDR 125 MHz 域慢角建立余量 +0.820 ns。此位流已覆盖同路径下的第一版恢复位流 `3EF6458D…`，**尚待实板验证**。

| 灯 | 新修复位流中的含义 |
| --- | --- |
| LED4 | 显示读适配器累计错误非零，锁存至 DDR 复位；此前细分诊断定位到缓冲距离异常 |
| LED5 | 读仲裁器累计错误非零，锁存至 DDR 复位 |
| LED6 | 当前显示通路允许输出（实时状态） |
| LED7 | 输出 DE 期间曾出现非零 RGB，锁存至 DDR 复位 |

烧录连续预取位流后，应先确认画面是否持续完整、LED6 是否稳定，以及 LED4、LED5 是否点亮；只有实板通过后才能宣称闪屏问题解决。

## 连续预取版实板失败与 CDC 缺陷复现

用户烧录 `88CA1504…` 后反馈灯态未变、画面更严重；照片显示顶部窄条有图像，其余大部分为黑屏。此版未通过实板验收，不能继续把增加预取作为已证实的根因修复。

重新核查发现，`rd_buf.v` 使用组合赋值 `consumed_gray = (consumed_beats >> 1) ^ consumed_beats`。二进制计数器的多位输出在进位时可能先后变化，组合 Gray 输出会出现中间值。DDR 域两级同步器只能同步收到的各位，不能把这种组合毛刺恢复成正确的 Gray 状态。`88CA1504…` 对应的布线后网表证实，消费计数器输出经过 XOR LUT 后直接进入 `display_adapter/consumed_meta`，源端没有 Gray 寄存器。

这处缺陷也解释了为什么预取更深可能使错误更易触发：缓冲接近满载时，错误的消费指针倒退就会把计算出的占用量推到 512 以上。以前的零延迟 RTL 仿真没有模拟二进制计数器各位的传播差，所以未覆盖这一失败机制。常规时序报告中的 `All Constraints Met` 也不等于异步 CDC 逻辑正确。

本次在 `Run-DisplayReadTiming.ps1` 添加可选 `-InjectCounterSkew`，仅在仿真副本中将计数器低 9 位更新延迟设为 0.1 ns、高位设为 2.1 ns；稳定计数值、DDR 服务模型均不变。这是定向故障注入，不是对实板延迟的测量。旧版在 493.060 µs 出现：

```text
actual_consumed=512 synchronized=0 produced=992 occupied=992 reserved=16
```

真实未读量应为 `992-512=480` beat，仍有数据；错误同步值让占用量变为 992，并触发帧阻断。日志位于 `fpga/sim/.work/display_read_timing-6be85e9b/xsim.log`。因此已证实原来的缓冲错误指示可以误报，不能把所有 LED4 事件当作真实 DDR 欠读。

独立工程 `fpga/project/stage3_dual_pool_copy_cdc_fix` 将 Gray 编码结果在 `vout_clk` 上寄存，再交给原有 DDR 域同步器。和 `88CA1504…` 恢复工程比较，`source/` 下仅 `rd_buf.v` 不同，功能修改限于消费指针源端注册；LED 映射保持上表含义。工程生成脚本也已同步这项修复。

修复后的两帧 720 行仿真在正常延迟及相同进位延迟注入下均通过，分别核对 230,400 个返回 beat 和 14,400 个突发地址，并包含原有的 30 µs DDR 等待、指针回绕和帧重置。日志分别为 `display_read_timing-311e5c1b/xsim.log` 和 `display_read_timing-94cdade2/xsim.log`。该测试核查显示读地址、完成条件与缓冲控制，RAM 输出仍为常量模型，不代表实板图像内容验收。

CDC 缺陷已有代码、网表和定向复现支持；它是否是当前实板闪屏的唯一原因，仍需修复位流上板确认。

本次 PDS 全流程成功，受约束路径 `All Constraints Met`，DDR 域慢角建立余量 +0.798 ns。布线后网表逐位核对了全部 10 位 Gray 指针：源端像素时钟触发器 Q 直接连接 DDR 第一同步级 D，再直接进入第二同步级，中间没有组合逻辑。Gray 最高位与二进制最高位同值，被工具合并为同一源端触发器。慢角 SDF 中，源触发器 CK-Q 加到第一同步级 D 的布线延迟最大为 0.855 ns，详细记录在新工程的 `cdc-netlist-audit.txt`。

板测位流：`fpga/project/stage3_dual_pool_copy_cdc_fix/generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`，大小 9,188,552 字节，SHA-256 `F332443546E9CDA0E2EE2CF346D7FC71988B35B42642E664718070BB33B884FB`。用户反馈烧录后画面正常、LED4 和 LED5 熄灭，其余灯正常。此版已有正常画面的实板反馈，但尚未记录运动画面连续运行 30 分钟，因此仍是最新板测候选，长期稳定验收未完成。已验收回退版本仍为 `stage3_frame_pool_gate_fix`。

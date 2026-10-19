# RGBX8888 测试页实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建一个可离线使用的单文件 HTML，帮助操作者检查 RGBX8888 视频链路图案、运行稳定性和人工事件记录。

**Architecture:** 页面用固定 1280×720 Canvas 绘制测试图，CSS 仅负责适配视口和控制面板。JavaScript 管理纯色、条纹、棋盘格、动画帧计数、秒表、事件列表和 CSV 下载；不读取硬件信号或推断 FPGA 实际帧率。

**Tech Stack:** 原生 HTML、CSS、JavaScript Canvas API、浏览器全屏 API、Blob 下载；不引入依赖。

## Global Constraints

- 单个 HTML 文件包含全部结构、样式和脚本，不依赖网络、框架或外部资源。
- 主测试画布使用 1280×720 逻辑像素，适配浏览器可用区域并保持宽高比。
- 图案包含红、绿、蓝、白、黑纯色，RGB 交替条纹、棋盘格和运动帧计数。
- 可开始、暂停、重置计时；可分别记录闪屏、丢帧和欠读事件并导出 CSV。
- 帧编号只显示页面动画状态，不将其作为 HDMI/FPGA 实测帧率。

---

### Task 1: 创建离线测试页

**Files:**
- Create: `host/test_patterns/rgbx8888_link_test.html`

**Interfaces:**
- 页面交互由 `setPattern(patternId)`、`startTimer()`、`pauseTimer()`、`resetSession()`、`recordEvent(eventType)`、`downloadCsv()` 实现。
- 图案标识为 `red`、`green`、`blue`、`white`、`black`、`stripes`、`checkerboard`、`motion`；事件标识为 `flicker`、`dropped-frame`、`underflow`。
- Canvas 固定为 `1280×720` 逻辑坐标；运动图案每次动画帧绘制时递增序号。

- [ ] 建立独立的测试页文件，包含语义化按钮、1280×720 Canvas、运行计时和事件记录区；所有控件使用可读的中文名称。
- [ ] 增加纯色与交替图案渲染：纯色用 `fillRect` 填满 Canvas；RGB 条纹按 1 像素竖条交替红绿蓝；棋盘格按 32×32 像素单元交替黑白。
- [ ] 增加运动图案：绘制固定网格、每帧递增的序号以及水平移动的高对比度方块；用 `requestAnimationFrame` 驱动画面。
- [ ] 增加控制面板：选择图案、开始/暂停/重置计时、全屏按钮、事件计数和事件时间列表；按 `F` 隐藏/显示控制面板并请求/退出全屏，输入框聚焦时不拦截按键。
- [ ] 记录本地会话开始时刻、累计运行秒数和人工事件；每类事件按钮递增计数并附带相对运行时间和本地时刻。
- [ ] 实现 CSV 下载，列出会话开始时间、总运行秒数、事件类型、相对秒数和记录时刻；字段使用双引号转义，文本使用 UTF-8 BOM 便于常见表格软件打开。
- [ ] 完成文件后检查脚本语法和控件引用，确认无需网络资源；不声称验证真实 HDMI 帧率或 FPGA 错误信号。


# PGL50H Cache 资源收敛与 1080p30 吞吐保持实施计划

> **For agentic workers:** 本计划按任务顺序实施；每项任务先跑失败测试，再做最小 RTL 改动，再完成规定回归。用户要求本阶段不提交 Git。

**Goal:** 在 PGL50H 上保留 32 sets × 8 ways、128 KiB RGBX Tile Cache 的命中率与 1080p30 吞吐能力，同时将 Cache 数据阵列从 LUTRAM 映射到 GTP_DRM18K。

**Architecture:** Cache 保持 4 个物理 Bank、每 Bank 128 bit、每字 4 个 RGBX8888 像素。每个 Bank 使用一个 2048×128 的同步简单双口 DRM（一个读口、一个写口）；Tag 查找、DRM 读地址和响应选择分成可停顿流水级。Pango IP 的真实读延迟先由专用测试测定并固化为 `BANK_READ_LATENCY`，无论是一拍还是两拍，读端口的 initiation interval 必须为 1，因此命中流仍可每拍接受一项、每拍返回一项。miss 在 Tag 阶段立即启动 fill，不等待无意义的 DRM 读周期；额外读延迟只影响帧首尾固定拍数。

**Tech Stack:** SystemVerilog、Pango PDS 2022.2-SP6.4、PGL50H GTP_DRM18K / `ipml_sdpram`、XSim 图像与吞吐回归。

## 全局约束

- 目标顶层固定为 `pgl50h_board_top`，其 Cache 参数固定为 `TILE_CACHE_SET_COUNT=32`、`TILE_CACHE_WAYS=8`。
- 图像格式保持 RGBX8888 Cache、RGB888 插值输出；DDR burst 协议、Tile 尺寸 32×4、256 bit 读数据接口不改变。
- `SET_COUNT` 必须为 2 的幂；PGL50H 硬件实现固定为 32，因此 set index 只能使用低 5 bit，禁止硬件 `%`。
- 1080p30 预算为 100 MHz 下 `3,333,333 cycles/frame`；图片回归必须 RGB888 逐像素一致。
- PDS 资源硬门限：总 LUT ≤ 42,800、LUTRAM ≤ 17,000、DRM18K ≤ 134；工程目标为 LUT ≤ 40,000、LUTRAM ≤ 2,000、DRM18K ≤ 120，给布局布线留下余量。
- 不以缩减 Cache 容量换吞吐：PGL50H 硬件 Cache 仍为 32×8×32×4×4 bytes = 128 KiB。
- 每项 RTL 改动后都运行对应 XSim 回归；本计划不执行 Git 提交。

---

## 资源根因与设计边界

当前 PDS 日志显示 `GTP_RAM32X1DP=100192`、LUTRAM=100264、总 LUT=151564。根因是 `pixel_tile_cache.sv` 的四个 `reg [127:0] bank*_mem` 被组合函数 `read_pixel_word()` 异步读取，同时 Tag 查询使用 `integer`、`/` 和 `%`。PDS 无法把这种异步、动态寻址阵列推断为 DRM，于是将数据 Cache 展开成 LUTRAM。

目标存储量计算如下：

| 项目 | 数值 |
| --- | ---: |
| 每 Bank 深度 | 32 sets × 8 ways × 8 words/tile = 2048 words |
| 每 Bank 宽度 | 128 bit |
| 每 Bank 容量 | 262,144 bit |
| 四 Bank 容量 | 1,048,576 bit = 128 KiB |
| 预计 Cache DRM18K | 60～64 个；以 PDS 实际报告为准 |
| 当前非 Cache DRM18K 基线 | 约 33.5 个 |
| 预计总 DRM18K | 约 94～98 个，低于 134 个 |

`clkout0` 的 74.25 MHz 约束不是本次资源膨胀的根因。同步 DRM 的固定读延迟必须通过流水线隐藏，而不是通过降低 Cache sets 或降低输出像素率规避。

### 吞吐保证的定量条件

当前完整图片基线是 3,237,697 cycles，1080p30 硬预算是 3,333,333 cycles，余量为 95,636 cycles，即 0.95636 ms / frame。当前统计 `commands=94,576`，每个 Tile miss 产生 4 条行命令，因此共有 23,644 次 Tile fill；`beats=378,304` 也等于 23,644 × 16 beat/tile。

这意味着不能接受“每个 miss 多等几拍”的实现：若每个 miss 增加 4 拍，就会额外消耗 94,576 拍，几乎吃光全部帧余量。因此最终架构必须同时满足：

```text
hit initiation interval = 1 cycle
miss detection overhead versus current design = 0 repeated cycle/miss
DDR commands and beats = unchanged
only frame start/drain fixed latency may increase, allowance <= 32 cycles
```

所以强验收不是仅仅低于 3,333,333，而是低于 3,237,729，并保持 commands、beats 与当前基线完全一致。

### Task 1: 固化资源与吞吐基线

**Files:**

- Create: `sim/check_pgl50h_cache_resource_report.ps1`
- Modify: `sim/tb_1080p30_throughput.sv`
- Test: `sim/run_1080p30_throughput.ps1`
- Test: `sim/run_mes50hp_top_cache_image_1080p.ps1`

**Interfaces:**

- Consumes: PDS `pds.log` 中的 `GTP_RAM32X1DP`、`Total LUTs`、`Total DRM18K` 行。
- Produces: 可重复执行的资源门限检查，以及 `frame_cycles <= 3333333` 的 XSim 断言。

- [x] **Step 1: 将当前报告保存为失败基线**

从 `boards/pgl50h/pds/pgl50h_rtl_synth/pds.log` 记录以下数值：

```text
GTP_RAM32X1DP = 100192
Total LUTs    = 151564 of 42800
Total DRM18K  = 33.5 of 134
```

该记录用于证明后续改动确实消除了 LUTRAM 展开；不能把旧日志中的其他历史运行混入本次解析。

- [x] **Step 2: 写资源门限检查脚本并验证它对旧报告失败**

脚本必须只解析最后一个 `Mapping Summary:` 之后的映射统计，并要求：

```powershell
if ($lut -gt 42800 -or $lutRam -gt 17000 -or $drm18k -gt 134) {
    throw "PGL50H resource overflow: LUT=$lut LUTRAM=$lutRam DRM18K=$drm18k"
}
```

对当前日志运行时预期失败，错误文本包含 `PGL50H resource overflow`。

- [x] **Step 3: 加强吞吐预算断言**

在 `tb_1080p30_throughput.sv` 的帧结束检查中保留并明确使用：

```systemverilog
if (frame_cycles > 3_333_333) begin
    $fatal(1, "TEST_FAIL: 1080p30 budget exceeded cycles=%0d", frame_cycles);
end
```

禁止把测试改成只检查平均值或只检查没有超时。

- [x] **Step 4: 运行吞吐与图片回归**

```powershell
.\sim\run_1080p30_throughput.ps1
.\sim\run_mes50hp_top_cache_image_1080p.ps1 -CacheSets 32
```

预期：吞吐测试通过；图片回归输出 `TEST_PASS: mes50hp_top_cache_image` 与 `PASS: RGB888 frames match (1920x1080)`；当前完整帧基线为 3,237,697 cycles。

### Task 2: 接入 PGL50H 专用 128×2048 DRM Bank IP

**Files:**

- Create: `rtl/vendor/pgl50h/memory/pgl50h_tile_cache_bank_ip.v`
- Modify: `boards/pgl50h/pds/pgl50h_rtl_synth/pgl50h_rtl_synth.pds`
- Create: `rtl/platform/common/memory/tile_cache_bank_ram.sv`
- Create: `sim/pgl50h_tile_cache_bank_ip_model.sv`
- Modify: `boards/pgl50h/pds/pgl50h_rtl_synth/pgl50h_rtl_synth.pds`
- Test: `sim/tb_tile_cache_bank_ram.sv`
- Test: `sim/run_tile_cache_bank_ram.ps1`

**Interfaces:**

- Consumes: `wr_en`, `wr_addr[10:0]`, `wr_data[127:0]`, `rd_en`, `rd_addr[10:0]`。
- Produces: `rd_data[127:0]` 和 `rd_valid`；`rd_valid` 相对 `rd_en` 延迟 `BANK_READ_LATENCY` 拍。
- Storage contract: 同一 Bank 每拍最多一写一读；连续读地址可以每拍输入一次；写端口和读端口都使用算法时钟 `clk`。

- [x] **Step 1: 先创建同步 RAM 时序失败测试**

测试必须覆盖以下序列：

```systemverilog
// 连续 32 拍均令 rd_en=1，并每拍改变 rd_addr。
// 从第 BANK_READ_LATENCY 拍开始，rd_valid 必须连续 32 拍为 1。
// 每个 rd_data 必须对应 BANK_READ_LATENCY 拍之前的地址。
// 同时写另一个地址，证明一读一写可并行且没有吞吐空泡。
```

初始行为模型尚未实现时，测试应因模块不存在或读延迟不符而失败。

- [x] **Step 2: 复用已导入的 Pango SDPRAM 原语包装**

在 PDS 中新建 `SDPRAM` IP，配置必须为：

```text
Device: PGL50H / FBG484 / -6
Write width: 128
Write address width: 11
Read width: 128
Read address width: 11
Read output register: enabled（优先保证 100 MHz 时序）
Read clock enable: enabled（由 rd_en / pipeline advance 驱动）
Read output clock enable: enabled（backpressure 时保持输出）
Write/read clock: 同一 clk
Reset: async assert, sync release 或与现有 RAM IP 一致
```

本实现使用 `rtl/vendor/pgl50h/memory/pgl50h_tile_cache_bank_ip.v` 作为综合包装，参数化调用 PDS 工程已经导入的 `ipml_sdpram_v1_6_rd_fram_buf` 源，固定为 128 bit × 2048、读输出寄存器开启、读写同一算法时钟。它不实例化 `rd_fram_buf` 的 256-bit/32-bit 顶层模块，只复用其底层 Pango SDPRAM 源，避免手工伪造 `.idf`。XSim 使用同名行为模型；Bank 测试实测当前模型为 1 拍读延迟，PDS 首次重新 Compile 后仍需确认原语报告的实际延迟。

- [x] **Step 3: 实现跨仿真/综合包装器**

`tile_cache_bank_ram.sv` 的公开接口固定如下：

```systemverilog
module tile_cache_bank_ram #(
    parameter integer BANK_READ_LATENCY = 1
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         wr_en,
    input  wire [10:0]  wr_addr,
    input  wire [127:0] wr_data,
    input  wire         rd_en,
    input  wire [10:0]  rd_addr,
    output wire [127:0] rd_data,
    output wire         rd_valid
);
```

包装器始终实例化模块 `pgl50h_tile_cache_bank_ip`。PDS 编译使用 `rtl/vendor/pgl50h/memory/pgl50h_tile_cache_bank_ip.v`；XSim 脚本只编译 `sim/pgl50h_tile_cache_bank_ip_model.sv`，由该文件提供同名、同端口的同步行为模型。这样不依赖 PDS 宏，也不会出现真实 IP 与包装器同名递归或重复定义。包装器用长度为 `BANK_READ_LATENCY` 的 valid 移位寄存器生成 `rd_valid`。

- [x] **Step 4: 运行 Bank IP 回归**

```powershell
.\sim\run_tile_cache_bank_ram.ps1
```

预期：`TEST_PASS: tile_cache_bank_ram`，并且 32 个连续读取无空泡、读写并发、读延迟和复位均通过。只有测得延迟与 `BANK_READ_LATENCY` 一致后才能接入 Cache。

### Task 3: 将 Tile Cache 变为四 Bank 同步读流水线

**Files:**

- Modify: `rtl/platform/common/memory/pixel_tile_cache.sv`
- Modify: `sim/tb_pixel_tile_cache.sv`
- Modify: `sim/tb_pixel_tile_cache_packed.sv`
- Test: `sim/run_pixel_tile_cache.ps1`
- Test: `sim/run_pixel_tile_cache_packed.ps1`

**Interfaces:**

- Consumes: 现有 `lookup_valid/lookup_ready`、`lookup_x0/y0`、fill 请求和 256-bit fill 数据接口。
- Produces: 保持不变的 `lookup_rsp_valid/lookup_rsp_ready` 和四个 32-bit 像素输出。
- Latency contract: 命中响应延迟为固定的 `TAG_PIPELINE_LATENCY + BANK_READ_LATENCY + RESPONSE_LATENCY`；连续命中在流水线灌满后每拍一个响应。

- [x] **Step 1: 写同步读 Cache 的失败测试**

在 warm-up 填充 Tile 后发送至少 16 个连续命中坐标，并检查：

```systemverilog
if (accepted_hits == 16 && returned_hits != 16)
    $fatal(1, "TEST_FAIL: cache did not retire one hit per cycle after pipeline fill");
if (rsp_before_configured_latency)
    $fatal(1, "TEST_FAIL: cache response arrived before configured latency");
```

同时保持四邻域像素与原 golden 值相同、跨 Tile 边界正确、miss 填充后重试正确。

- [x] **Step 2: 删除组合数据阵列与组合读函数**

删除：

```systemverilog
reg [BANK_WORD_WIDTH-1:0] bank0_mem [0:BANK_DEPTH-1];
// bank1_mem / bank2_mem / bank3_mem
function automatic [PIXEL_WIDTH-1:0] read_pixel_word;
```

替换为四个 `tile_cache_bank_ram` 实例。每个实例独立拥有一个读地址；由于 `TILE_W=32`、`TILE_H=4` 都是偶数，local parity 与全局像素 parity 一致，因此任意 2×2 邻域的 p00/p10/p01/p11 必然落在四个不同 Bank，即使跨 Tile 边界也成立，不需要复制 RAM 来制造多读口。

- [x] **Step 3: 固定算术为位操作**

在 PGL50H 固定配置下使用以下等价关系，禁止综合出通用除法器或取模器：

```systemverilog
tile_x  = source_x >> 5;          // TILE_W = 32
tile_y  = source_y >> 2;          // TILE_H = 4
local_x = source_x[4:0];
local_y = source_y[1:0];
raw_set = tile_x - tile_y + (tile_x >> 2);
set_idx = raw_set[4:0];           // mod 32，二补码低位天然正确
word_idx = {set_idx, way_idx, local_y[1], local_x[4:3]};
slot_idx = local_x[2:1];
```

加 elaboration-time 检查：硬件分支仅允许 `TILE_W==32`、`TILE_H==4`、`SET_COUNT==32`、`WAYS==8`，不满足时 `$error`，防止用错误参数综合。

PGL50H 验收仿真统一使用 32 sets；原先用于探索的 48-set 配置不再进入硬件接入回归，因为 2048 深度 Bank 只能覆盖最多 32 sets × 8 ways × 8 words。16-set 行为测试可以保留，但最终图片、吞吐和 PDS 测试必须固定 32 sets。

- [x] **Step 4: 建立同步 Bank 命中流水线**

实现以下状态/寄存器边界：

```text
L0A: 接收 lookup；用移位计算 Tile/local/set，并识别 x/y Tile 边界
L0B: 比较有效位与最多四组 Tag；hit 才发出四 Bank 读地址
L1..Ln: 等待 BANK_READ_LATENCY；逐拍携带 slot、coord_valid 和次序令牌
LR: 捕获四个 128-bit word，从各 word 选出一个 32-bit 像素并发出响应
```

所有级使用 valid/ready；当 `lookup_rsp_ready=0` 时冻结响应寄存器并向前传播 backpressure，禁止丢失或重排坐标。Tag miss 在 L0B 已经确定，因此不向 DRM 发读请求，而是立即锁存 `pending_tile/pending_set/pending_way`、清除该 victim 的 valid 位并启动 `STATE_FILL_REQ`。Cache 从接受这个 miss 起停止接受后续 lookup，但此前已发出的 hit 允许继续从 DRM 返回和排空；不能为了等待流水线清空给每个 miss 增加额外周期。清除 victim valid 可避免 fill 写入期间旧 Tag 命中半覆盖数据。

- [x] **Step 5: 保持 fill 吞吐并处理读写并发**

每个 256-bit beat 仍写入两个 active Bank，每个 active Bank 只写一个 128-bit word：

```text
even row: Bank0 + Bank1
odd row : Bank2 + Bank3
```

DRM 的读端口可同时服务命中流水线，写端口服务 fill。Tile 的 `valid_mem` 只能在第 4 行、第 4 个 beat 写完后置位；fill 中 Tile 始终视为 miss，防止读到半填充数据。

数据 DRM、Tag 和 LRU 数组都不做全阵列复位；复位只清除 256 个 `valid_mem` 位。Tag/LRU 在 valid=0 时属于 don't-care，并在分配/命中更新时写入。这样避免为几千位状态制造异步复位网络和额外控制集合。

- [x] **Step 6: 运行单元回归**

```powershell
.\sim\run_pixel_tile_cache_packed.ps1
.\sim\run_pixel_tile_cache.ps1
```

预期：两个测试都输出 `TEST_PASS`；连续命中不出现空泡；四邻域、边界、fill 后命中均与改动前一致。

### Task 4: 对齐 Fetch 元数据并保持帧级吞吐

**Files:**

- Modify: `rtl/platform/common/memory/cached_pixel_fetch_engine.sv`
- Modify: `sim/tb_cached_pixel_fetch_throughput.sv`
- Modify: `sim/tb_cached_pixel_fetch_stress.sv`
- Modify: `sim/tb_1080p30_throughput.sv`
- Test: `sim/run_cached_pixel_fetch_throughput.ps1`
- Test: `sim/run_cached_pixel_fetch_stress.ps1`
- Test: `sim/run_1080p30_throughput.ps1`

**Interfaces:**

- Consumes: Cache 的参数化固定延迟命中响应和 `lookup_ready` 回压。
- Produces: 与响应一一对应的 `fx`、`fy`、`sof`、`eol`，再输入 `bilinear_interp`。
- Throughput contract: 灌满后 `in_valid && in_ready` 可连续为 1；命中输出连续为 1；不得因同步 DRM 让 hit path 变成隔拍。

- [x] **Step 1: 以吞吐回归暴露并修复元数据错位**

构造连续输入，其中每项 `fx`、`fy`、`sof`、`eol` 都不同，检查插值输出对应同一坐标：

```systemverilog
if (out_sof !== expected_sof[out_index] || out_eol !== expected_eol[out_index])
    $fatal(1, "TEST_FAIL: fetch metadata is misaligned at output %0d", out_index);
```

修改前该测试应因 Cache 新增延迟导致的元数据提前消费而失败。

- [x] **Step 2: 用深度 8 的 metadata FIFO 替换单一 `pending_reg` 假设**

实现深度为 8 的顺序 FIFO，项格式固定为：

```systemverilog
typedef struct packed {
    logic [15:0] fx;
    logic [15:0] fy;
    logic        sof;
    logic        eol;
} fetch_meta_t;
```

入队条件为 `cached_input_fire`；出队条件为 `cache_rsp_valid && cache_rsp_ready`。深度 8 覆盖 L0A、L0B、最多两拍 DRM 输出和响应寄存器，并留有 backpressure 余量。`in_ready` 必须同时受 FIFO 空间和 `cache_lookup_ready` 控制。禁止以延迟计数器猜测响应时刻。

- [x] **Step 3: 保持 miss 行为和坐标 FIFO 解耦**

`coordinate_fifo` 深度保持 544，DDR 命令、burst 长度、单未完成读协议不改。同步 DRM 改动只影响 Cache hit 数据返回；miss 的 4 行 × 4 beat 填充流程不增加任何 DDR beat，也不改变 `commands`/`beats` 统计。

- [x] **Step 4: 运行 Fetch 与帧周期回归**

```powershell
.\sim\run_cached_pixel_fetch_throughput.ps1
.\sim\run_cached_pixel_fetch_stress.ps1
.\sim\run_1080p30_throughput.ps1
```

预期：命中流维持 1 pixel/cycle；压力回归无死锁；完整帧首先要求 `frame_cycles <= 3,237,729`（当前 3,237,697 + 最多 32 拍固定启动/排空余量），因此仍完整保留约 95,600 拍的 1080p30 安全余量。同步读不允许给每个 hit 或每个 miss 增加重复周期。

### Task 5: 图片级回归与 PDS 资源闭环

**Files:**

- Modify: `boards/pgl50h/pds/pgl50h_rtl_synth/pgl50h_rtl_synth.pds`
- Modify: `sim/check_pgl50h_rgbx_pds_sources.ps1`
- Test: `sim/run_mes50hp_top_cache_image_1080p.ps1`
- Test: `sim/check_pgl50h_cache_resource_report.ps1`
- Test: PDS `Compile` → `Synthesize` → resource/timing report

**Interfaces:**

- Consumes: 新 DRM IP `.idf/.v`、包装器和 32×8 固定 Cache 配置。
- Produces: PDS 可导入工程、资源报告和 100 MHz 时序报告。

- [x] **Step 1: 更新 PDS 导入清单**

将 `tile_cache_bank_ram.sv` 与 `rtl/vendor/pgl50h/memory/pgl50h_tile_cache_bank_ip.v` 加入 PDS 普通 RTL 清单。PDS 不导入 `sim/pgl50h_tile_cache_bank_ip_model.sv`；XSim 不导入真实 Pango IP RTL。保留原 `pixel_tile_cache.sv`、`cached_pixel_fetch_engine.sv` 和 1080p30 top 的唯一引用；不得保留旧的 Cache 行为 RAM 作为 PDS 综合源。

- [ ] **Step 2: PDS Compile 待在 PDS GUI 中刷新旧解析缓存后复核**

在 PDS 先执行 Compile，确认无模块重复、无 IP version mismatch、无 `bmsSMOD` 来自 `pixel_tile_cache.sv`。再执行 Synthesize；本任务不进入布局布线，直到资源检查通过。

- [ ] **Step 3: 运行资源门限检查（等待新的 PDS 报告）**

```powershell
.\sim\check_pgl50h_cache_resource_report.ps1
```

预期：`GTP_RAM32X1DP` 从约 100,192 降至小量 tag/FIFO 使用；总 DRM18K 不超过 120；总 LUT 不超过 40,000。若任一硬门限失败，停止布局布线，回到 Task 3 检查是否仍存在数组异步读或通用除法/取模。

- [x] **Step 4: 跑 1080p 图片回归并比较统计**

```powershell
.\sim\run_mes50hp_top_cache_image_1080p.ps1 -CacheSets 32
```

预期：输出 2,073,600 像素，`PASS: RGB888 frames match (1920x1080)`。`commands=94576`、`beats=378304` 必须与当前基线一致；总 `cycles` 必须不大于 3,237,729。若命令数增加，说明替换策略或 Tag/valid 时序改变，不能用“仍低于 3,333,333”作为接受理由。

- [ ] **Step 5: 仅在资源通过后进行时序闭环**

检查 PDS 中 `video_pixel_clk` 的 74.25 MHz 约束、`sys_clk` 50 MHz 约束，以及最差 setup/hold slack。若 100 MHz 算法域的路径不通过，只在 Tag 查找、Bank 地址寄存和响应选择之间增加寄存器；禁止降低 Cache 容量或降低输出帧率作为首选修复。

## 验收表

| 维度 | 必须满足 |
| --- | --- |
| 功能 | 1920×1080 RGB888 golden 与 RTL 逐像素一致 |
| 吞吐 | 强验收 `cycles/frame <= 3,237,729`；硬预算仍为 3,333,333，对应 100 MHz 下 1080p30 |
| Cache 容量 | 32 sets × 8 ways、128 KiB，不缩容 |
| DDR 流量 | commands=94,576、beats=378,304 不因同步读增加 |
| 存储映射 | Cache 数据主体映射到 GTP_DRM18K，不再展开为约 100k LUTRAM |
| PGL50H 资源 | LUT ≤ 42,800、LUTRAM ≤ 17,000、DRM18K ≤ 134 |
| 时钟 | 74.25 MHz nominal video constraint 与重生成 PLL 一致 |

## 不采用的方案

- 不把 32-set Cache 直接缩到 4/8 sets：资源会下降，但命中率下降会增加 DDR miss，无法保证 1080p30。
- 不用单端口 RAM 复用读写：fill 与 hit 会互相抢占端口，引入额外空泡并损害吞吐。
- 不继续依赖 `reg` 数组异步读，让工具“自动推断 BRAM”：本次 PDS 报告已证明该推断在 PGL50H 上失败。
- 不在没有官方 DDR outstanding 协议证据时加入多未完成读和返回重排；本计划用现有单读事务协议完成资源收敛。

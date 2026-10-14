# MES50HP 时钟与 CDC 规划

## 1. 板载参考时钟

MES50HP硬件手册给出的板载时钟为：

| 时钟 | PGL50H管脚 | 用途 |
|---|---|---|
| 50 MHz单端 | P20 | 系统逻辑、I²C配置和低速控制参考 |
| 27 MHz单端 | K21 | 视频相关参考时钟候选，具体用途按官方例程确认 |
| 125 MHz差分 | A10/B10 | HSST参考时钟，本项目基础视频链暂不使用 |

HDMI输入还会由MS7200向FPGA提供独立的`HD_RX_PCLK`。DDR3 IP和HDMI输出也会形成各自的用户或像素时钟域。

## 2. 预期时钟域

```text
sys_clk_domain
  └── 50 MHz系统控制、I²C、状态机

hdmi_rx_domain
  └── MS7200输出PCLK、RGB/HS/VS/DE采集

ddr_user_domain
  └── DDR3 IP用户接口、Frame Buffer读写

processing_domain
  └── 畸变坐标、Pixel Fetch调度和图像算法

hdmi_tx_domain
  └── MS7210输入PCLK、RGB/HS/VS/DE输出
```

这些时钟域不得默认同频或同相。实际PLL频率、DDR用户时钟和像素时钟只有在官方例程、IP配置及PDS时序报告确认后才能冻结。

## 3. CDC规则

### 3.1 单bit状态信号

稳定电平跨域使用两级同步触发器。脉冲信号不能直接通过两级同步器，必须使用脉冲展宽、toggle同步或请求/应答握手。

### 3.2 多bit配置

畸变参数、图像尺寸和阈值等配置只在帧间更新。配置数据先稳定，再通过握手通知目标时钟域在帧首锁存。

### 3.3 像素流

```text
pixel_data
valid
sof
eol
```

必须作为一个整体通过异步FIFO或帧缓存跨域，不能分别使用普通同步器。

### 3.4 复位

每个时钟域遵守：

```text
异步置位（若板级方案需要）
同步释放
```

每个域使用自己的复位同步器。不能把某一时钟域同步后的复位直接用于另一时钟域。

## 4. 推荐数据路径

```text
MS7200 / RX PCLK
        ↓
RX Async FIFO
        ↓
DDR Write / User Clock
        ↓
Ping-Pong Frame Buffer
        ↓
Processing Clock + Pixel Cache
        ↓
TX Async FIFO
        ↓
MS7210 / TX PCLK
```

若最终处理链与DDR用户接口共用一个时钟域，可以减少一次跨域，但必须以PDS时序和DDR IP接口要求为依据。

## 5. 验证要求

- [ ] 每个时钟在约束文件中有明确周期；
- [ ] 所有派生时钟由PDS正确识别；
- [ ] 异步时钟组在约束中明确声明；
- [ ] CDC结构通过人工审查或工具检查；
- [ ] 异步FIFO覆盖接近满、接近空、上溢和下溢；
- [ ] RX和TX频率存在小偏差时不发生画面撕裂；
- [ ] 复位释放不会产生伪`sof/eol/valid`；
- [ ] 端到端延迟按时钟域分别测量并换算为时间。

## 6. 资料来源

- MES50HP硬件使用手册：<https://szlogicmatrix.com/wp-content/uploads/2025/12/MES50HP%E5%BC%80%E5%8F%91%E6%9D%BF%E7%A1%AC%E4%BB%B6%E4%BD%BF%E7%94%A8%E6%89%8B%E5%86%8C_1V1.pdf>

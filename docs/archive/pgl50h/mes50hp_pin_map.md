# MES50HP 接口与引脚资料索引

## 1. 使用原则

本文件记录已经由MES50HP硬件手册确认的关键接口。完整24位HDMI数据总线、DDR3管脚和IO电平标准应从官方示例工程及最新版硬件手册导入，再与开发板实物版本核对。

不要根据网络文章手工拼接完整约束文件，也不要沿用EU-22K/PGL22G的任何管脚约束。

## 2. 关键时钟

| 信号 | PGL50H管脚 |
|---|---|
| `FPGA_GCLK_50M` | P20 |
| `FPGA_GCLK_27M` | K21 |
| `HSST_CLK_P` | A10 |
| `HSST_CLK_N` | B10 |

## 3. HDMI输入控制信号

MS7200通过24位并行接口向FPGA输出视频：

| 信号 | PGL50H管脚 |
|---|---|
| `HD_RX_PCLK` | AA12 |
| `HD_RX_VS` | W13 |
| `HD_RX_HS` | V13 |
| `HD_RX_DE` | U13 |
| `HD_SCL` | V19 |
| `HD_SDA` | V20 |

数据总线`HD_RX_D[23:0]`以及复位、中断和音频信号应从官方MES50HP约束或手册表3-6完整导入。

## 4. HDMI输出控制信号

FPGA通过24位并行接口向MS7210输入视频：

| 信号 | PGL50H管脚 |
|---|---|
| `HD_TX_PCLK` | M22 |
| `HD_TX_VS` | W20 |
| `HD_TX_HS` | Y21 |
| `HD_TX_DE` | Y22 |
| `HDMI_TX_SCL` | P17 |
| `HDMI_TX_SDA` | P18 |

数据总线`HD_TX_D[23:0]`以及复位、中断和音频信号应从官方MES50HP约束或手册表3-7完整导入。

## 5. DDR3

DDR3连接到PGL50H Bank 3，使用两颗x16器件组成x32总线。DDR3管脚、电平、时序和校准参数必须由MES50HP官方DDR3示例工程及匹配版本PDS IP生成，不在手写算法约束中重复维护。

## 6. 上板前检查

- [ ] 核对开发板丝印和核心板版本；
- [ ] 核对DDR3实际器件型号；
- [ ] 从同一版本官方例程取得PDC/SDC和IP配置；
- [ ] 核对Bank电压与IO标准；
- [ ] 核对MS7200/MS7210的I²C地址和初始化表；
- [ ] 核对HDMI数据位顺序及RGB/YUV格式；
- [ ] 核对所有像素时钟输入输出管脚；
- [ ] 禁止复制PGL22G/EU-22K约束。

## 7. 资料来源

- MES50HP硬件使用手册：<https://szlogicmatrix.com/wp-content/uploads/2025/12/MES50HP%E5%BC%80%E5%8F%91%E6%9D%BF%E7%A1%AC%E4%BB%B6%E4%BD%BF%E7%94%A8%E6%89%8B%E5%86%8C_1V1.pdf>
- 紫光同创盘古50K开发板介绍：<https://www.pangomicro.com/open/4276.html>

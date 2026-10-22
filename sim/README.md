# 仿真

阶段 4 将在此放置小尺寸图像、坐标边界和定点计算的仿真输入及运行脚本。旧工程向量迁移时应记录来源版本，并使用真实 720p60 参数重新验证。

当前坐标链路仿真位于 `fpga/sim/`：

- `Run-IdentityMapper.ps1`：单位映射、Q16.16 雅可比、反压和复位。
- `Run-CoordinateFifo.ps1`：宽坐标队列顺序、非二次幂回绕、满队列同周期出入和复位。
- `Run-IdentityCoordinatePipeline.ps1`：mapper 与 FIFO 端到端随机停顿测试。
- `Run-BilinearSamplePlanner.ps1`：Q16.16 floor、负坐标、四邻域边界掩码、复制边缘、反压和元数据测试。
- `Run-BilinearInterpolator.ps1`：RGBX8888 四邻点插值、黑边掩码、末级舍入、满量程累加、反压和元数据测试。
- `Run-ProceduralPixelReader.ps1`：片上 RGBX8888 网格/渐变四邻点读取与黑边测试。
- `Run-DemoRadialMapper.ps1`：固定径向 Q16.16 算术、流水线反压和元数据测试。
- `Run-Stage4DemoPipeline.ps1`：径向映射到双线性输出的完整链路测试。
- `Run-Stage4DemoFrameSource.ps1`：小帧 HDMI 有效区扫描、像素序号和帧完成测试。
- `Run-Stage4DemoFramBuf.ps1`：板级 `fram_buf` 替换层、LED 诊断和 AXI 静默测试。
- `Run-Stage4DemoFullFrame.ps1`：完整 1280×720、921,600 像素逐点顺序测试。

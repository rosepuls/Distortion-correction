# 使用 xsim 仿真基础图像模块

_适用于本项目 `Distortion-correction` 目录中的 SystemVerilog RTL 和独立 testbench。_

---

## 📋 仿真流程

在 PowerShell 中依次运行 `xvlog`、`xelab`、`xsim`：

```text
RTL + testbench ──xvlog──> 编译 ──xelab──> 仿真快照 ──xsim──> PASS / FAIL
```

本项目的 testbench 会自行检查输出，成功时打印 `TEST_PASS`；检查失败时打印 `TEST_FAIL`。此流程验证 RTL 行为，不会运行 Python golden model，也不等于 PDS 综合。

## 🧰 运行前准备

打开 PowerShell，进入项目根目录（不是 `rtl` 子目录）：

```powershell
cd "C:\Study\IC_Study\Project\FPGA_Vivado\Contest\Pango_Micro_FPGA\Distortion-correction"
```

确认 Vivado Simulator 命令可用：

```powershell
Get-Command xvlog, xelab, xsim
```

如果能分别显示 `xvlog.bat`、`xelab.bat`、`xsim.bat` 的路径，就可以继续。若提示找不到命令，请先检查 Vivado `2020.2\bin` 是否已加入当前 PowerShell 的 `PATH`；也可以重新打开 PowerShell，让刚修改的环境变量生效。

## 🚀 仿真一个模块

以 `rgb2gray` 为例，逐行复制执行：

```powershell
xvlog -sv rtl\algorithm\preprocess\rgb2gray.sv sim\tb_rgb2gray.sv
xelab -debug typical tb_rgb2gray -s tb_rgb2gray_sim
xsim tb_rgb2gray_sim -runall
```

成功时应看到类似输出：

```text
TEST_PASS: rgb2gray
```

如果出现 `TEST_FAIL` 或 `$fatal`，本次仿真没有通过。先保留完整报错，再检查 RTL 与 testbench 的接口、时序和预期值。

## 📚 其他模块的复制命令

每组命令都包含“编译、生成快照、运行”三步。可以一次复制一组执行；不要把不同模块的 testbench 名称混用。

### brightness_gain

```powershell
xvlog -sv rtl\algorithm\preprocess\brightness_gain.sv sim\tb_brightness_gain.sv
xelab -debug typical tb_brightness_gain -s tb_brightness_gain_sim
xsim tb_brightness_gain_sim -runall
```

### coordinate_gen

```powershell
xvlog -sv rtl\algorithm\distortion\coordinate_gen.sv sim\tb_coordinate_gen.sv
xelab -debug typical tb_coordinate_gen -s tb_coordinate_gen_sim
xsim tb_coordinate_gen_sim -runall
```

该测试覆盖连续两帧、帧内坐标换行、空拍、SOF 重新同步和复位恢复。

### normalize

```powershell
xvlog -sv rtl\algorithm\distortion\normalize.sv sim\tb_normalize.sv
xelab -debug typical tb_normalize -s tb_normalize_sim
xsim tb_normalize_sim -runall
```

### coordinate_split

```powershell
xvlog -sv rtl\algorithm\distortion\coordinate_split.sv sim\tb_coordinate_split.sv
xelab -debug typical tb_coordinate_split -s tb_coordinate_split_sim
xsim tb_coordinate_split_sim -runall
```

### distortion_stream

```powershell
xvlog -sv rtl\algorithm\distortion\coordinate_gen.sv rtl\algorithm\distortion\normalize.sv rtl\algorithm\distortion\coordinate_split.sv rtl\algorithm\distortion\distortion_core.sv sim\tb_distortion_stream.sv
xelab -debug typical tb_distortion_stream -s tb_distortion_stream_sim
xsim tb_distortion_stream_sim -runall
```

该回归以连续两帧、帧内空拍、复位恢复和最后行/列边界检查整个坐标链的 `valid/sof/eol` 对齐。

### gamma_lut

```powershell
xvlog -sv rtl\algorithm\preprocess\gamma_lut.sv sim\tb_gamma_lut.sv
xelab -debug typical tb_gamma_lut -s tb_gamma_lut_sim
xsim tb_gamma_lut_sim -runall
```

### bilinear_interp

```powershell
xvlog -sv rtl\algorithm\interpolation\bilinear_interp.sv sim\tb_bilinear_interp.sv
xelab -debug typical tb_bilinear_interp -s tb_bilinear_interp_sim
xsim tb_bilinear_interp_sim -runall
```

### pixel_fetch_bilinear

```powershell
xvlog -sv rtl\algorithm\interpolation\bilinear_interp.sv rtl\platform\common\memory\pixel_fetch_if.sv rtl\platform\common\memory\pixel_fetch_engine.sv sim\models\ddr_behavior_model.sv sim\tb_pixel_fetch_bilinear.sv
xelab -debug typical tb_pixel_fetch_bilinear -s tb_pixel_fetch_bilinear_sim
xsim tb_pixel_fetch_bilinear_sim -runall
```

该测试验证 `P00/P10/P01/P11` 请求顺序、单请求响应握手、RGB888 双线性结果、无效边界坐标不发请求，以及 `sof/eol` 控制信号对齐。

### line_ram_1r1w

```powershell
xvlog -sv rtl\algorithm\preprocess\line_ram_1r1w.sv sim\tb_line_ram_1r1w.sv
xelab -debug typical tb_line_ram_1r1w -s tb_line_ram_1r1w_sim
xsim tb_line_ram_1r1w_sim -runall
```

### line_buffer_3x3

```powershell
xvlog -sv rtl\algorithm\preprocess\line_ram_1r1w.sv rtl\algorithm\preprocess\line_buffer_3x3.sv sim\tb_line_buffer_3x3.sv
xelab -debug typical tb_line_buffer_3x3 -s tb_line_buffer_3x3_sim
xsim tb_line_buffer_3x3_sim -runall
```

### window_3x3

```powershell
xvlog -sv rtl\algorithm\preprocess\window_3x3.sv sim\tb_window_3x3.sv
xelab -debug typical tb_window_3x3 -s tb_window_3x3_sim
xsim tb_window_3x3_sim -runall
```

### gaussian_3x3

```powershell
xvlog -sv rtl\algorithm\preprocess\gaussian_3x3.sv sim\tb_gaussian_3x3.sv
xelab -debug typical tb_gaussian_3x3 -s tb_gaussian_3x3_sim
xsim tb_gaussian_3x3_sim -runall
```

### sobel_3x3

```powershell
xvlog -sv rtl\algorithm\detect\sobel_3x3.sv sim\tb_sobel_3x3.sv
xelab -debug typical tb_sobel_3x3 -s tb_sobel_3x3_sim
xsim tb_sobel_3x3_sim -runall
```

### threshold

```powershell
xvlog -sv rtl\algorithm\detect\threshold.sv sim\tb_threshold.sv
xelab -debug typical tb_threshold -s tb_threshold_sim
xsim tb_threshold_sim -runall
```

### morphology

```powershell
xvlog -sv rtl\algorithm\detect\morphology.sv sim\tb_morphology.sv
xelab -debug typical tb_morphology -s tb_morphology_sim
xsim tb_morphology_sim -runall
```

## 🔎 常见问题

| 现象 | 检查方法 |
| --- | --- |
| `xvlog`、`xelab` 或 `xsim` 无法识别 | 检查 Vivado `bin` 是否在 `PATH`，然后重新打开 PowerShell |
| `module ... not found` | 确认 `xvlog` 命令同时编译了该模块 RTL 和对应 testbench |
| `Cannot find design unit` | 确认 `xelab` 的顶层名与 testbench 中的 `module` 名一致 |
| 输出 `TEST_FAIL` 或 `$fatal` | 仿真确实运行了，但检查值不匹配；记录输出并定位模块行为 |
| 想看波形 | 将最后一行改为 `xsim <快照名> --gui`，在 GUI 中添加信号后运行仿真 |

例如查看 `rgb2gray` 波形：

```powershell
xsim tb_rgb2gray_sim --gui
```

打开 GUI 后，添加 testbench 或 DUT 信号到波形窗口，再点击运行（Run All）。命令行 `-runall` 模式适合快速查看 PASS/FAIL。

## 📌 后续添加模块

新模块需要有 RTL 文件和独立的 `sim\tb_<模块名>.sv`。按照下面模板替换路径、testbench 顶层名和快照名：

```powershell
xvlog -sv <RTL路径> <testbench路径>
xelab -debug typical <testbench顶层名> -s <快照名>
xsim <快照名> -runall
```

每次优先单独运行一个模块。确认出现 `TEST_PASS` 后，再记录该模块的仿真结果。
# 当前 720p 主回归

当前板级主路径为 1280×720@30fps，完整 RGBX Cache 图片回归和吞吐率回归分别运行：

```powershell
powershell -ExecutionPolicy Bypass -File sim/run_mes50hp_top_cache_image_720p.ps1
powershell -ExecutionPolicy Bypass -File sim/run_720p30_throughput.ps1
```

1080p 脚本仍保留为历史基线，不作为当前 PGL50H 默认配置。

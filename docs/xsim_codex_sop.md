# Vivado XSim / Codex 仿真 SOP

本文档用于在本工程和后续 Codex 对话中稳定运行 Vivado Simulator 2020.2。

## 结论与适用范围

- Vivado 安装目录：`D:\Xilinx\Vivado\2020.2`
- 标准仿真顺序：`xvlog` → `xelab` → `xsim`。
- 在普通 Windows 终端中可直接执行这些命令。
- 在 Codex 的 Windows 沙箱中，Vivado 2020.2 自带的 MinGW/GCC 可能无法启动，表现为 `ERROR: [XSIM 43-3409] Failed to compile generated C file ...`。此时必须让 `xelab` 和 `xsim` 在沙箱外执行；不要修改 RTL、替换 GCC 或重装 Vivado。

已于 2026-10-04 使用 `tb_coordinate_fifo` 验证：`xelab` 成功生成 `coordinate_fifo_sim`，随后 `xsim -R` 输出 `TEST_PASS: coordinate_fifo` 并以退出码 0 结束。

## 新 Codex 对话的最短请求

将下面这段话发送给新对话即可：

> 请阅读 `Distortion-correction/docs/xsim_codex_sop.md` 并运行 XSim。Vivado 2020.2 位于 `D:\Xilinx\Vivado\2020.2`。为避免 `XSIM 43-3409`，请用绝对路径调用 `xelab.bat` 和 `xsim.bat`，并以沙箱外权限执行；先报告 `xvlog`、`xelab` 和 `xsim` 的退出码及 `TEST_PASS`/错误日志。

在 Codex 中，这意味着代理对 `xelab` 和 `xsim` 的命令调用需要设置 `sandbox_permissions: "require_escalated"`；这是运行环境的要求，不是工程脚本能够自行绕过的限制。

## 一次完整的 PowerShell 仿真

从任意 PowerShell 终端运行下列脚本。它以 `coordinate_fifo` 为例，所有 Vivado 临时产物都会位于该用例自己的 `xsim.dir` 目录中。

```powershell
$repo = 'C:\Study\IC_Study\Project\FPGA\Contest\Pango_Micro_FPGA\Distortion-correction'
$vivado = 'D:\Xilinx\Vivado\2020.2'
$caseDir = Join-Path $repo 'xsim.dir\coordinate_fifo'

if (-not (Test-Path "$vivado\bin\xvlog.bat")) {
    throw "Vivado 2020.2 was not found at $vivado"
}

New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
Push-Location $caseDir
try {
    & "$vivado\bin\xvlog.bat" -sv `
        "$repo\rtl\platform\common\memory\coordinate_fifo.sv" `
        "$repo\sim\tb_coordinate_fifo.sv"
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed with exit code $LASTEXITCODE" }

    & "$vivado\bin\xelab.bat" tb_coordinate_fifo -s coordinate_fifo_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab failed with exit code $LASTEXITCODE" }

    & "$vivado\bin\xsim.bat" coordinate_fifo_sim -R
    if ($LASTEXITCODE -ne 0) { throw "xsim failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}
```

成功标准：

1. `xvlog` 没有 `ERROR`，并分析 RTL 与 testbench。
2. `xelab` 输出 `Built simulation snapshot coordinate_fifo_sim`。
3. `xsim` 输出 `TEST_PASS: coordinate_fifo` 和 `XSIM_EXIT=0`（若由包装脚本打印退出码）。

`reserve_ready remains unconnected` 是当前 `tb_coordinate_fifo.sv` 的已知警告，不会阻止该仿真完成；不要将它误判为 43-3409 的成因。

## 为其他 testbench 套用

只需替换以下四项，流程不变：

| 项目 | `coordinate_fifo` 示例 | 替换为 |
| --- | --- | --- |
| 用例目录 | `xsim.dir\coordinate_fifo` | `xsim.dir\<case_name>` |
| RTL 文件 | `rtl\platform\common\memory\coordinate_fifo.sv` | 该用例所需的全部 RTL，按依赖顺序传给 `xvlog` |
| Testbench | `sim\tb_coordinate_fifo.sv` | 对应的 `sim\tb_*.sv` |
| 顶层与快照 | `tb_coordinate_fifo` / `coordinate_fifo_sim` | `tb_<name>` / `<name>_sim` |

始终从用例目录运行三条命令。这样 `xsim.log`、`xelab.log`、波形数据库和 `xsim.dir` 只会写到该用例目录，不会污染工程根目录。

## `XSIM 43-3409` 排障

### 典型症状

`xvlog` 和静态展开都通过，但 `xelab` 在以下阶段失败：

```text
Compiling module work.<module_name>
ERROR: [XSIM 43-3409] Failed to compile generated C file xsim.dir/<snapshot>/obj/xsim_<n>.c.
```

### 本环境的根因确认

在 Codex 沙箱内直接运行 Vivado 自带 GCC 会报 Windows 的“无效的系统 DLL 重定位”；即使将 `PATH` 缩减为 Vivado 和 Windows 系统目录，问题仍然出现。相同 GCC 在沙箱外可正常输出版本号：

```powershell
& 'D:\Xilinx\Vivado\2020.2\tps\mingw\6.2.0\win64.o\nt\bin\gcc.exe' --version
```

因此本问题由沙箱运行时与旧 MinGW 的兼容性造成，Vivado 安装和生成的 C 文件均不是根因。

### 处理顺序

1. 在新对话中要求代理将 `xelab`、`xsim` 以沙箱外权限执行，并使用 `D:\Xilinx\Vivado\2020.2\bin\xelab.bat` 与 `xsim.bat` 的绝对路径。
2. 重新运行 `xelab`。若输出 `Built simulation snapshot ...`，说明 GCC 阶段已经恢复。
3. 运行 `xsim <snapshot> -R`，以 testbench 的 `TEST_PASS` 和退出码 0 作为最终判断。
4. 只有沙箱外的 `gcc.exe --version` 也失败时，才排查 Vivado 安装、系统安全策略或 DLL 冲突；不要先修改工程 RTL。

## 日志与证据保存

每次仿真至少保留以下文件在 `xsim.dir\<case_name>`：

- `xvlog.log`：HDL 编译日志。
- `xelab.log`：静态展开、生成 C 和快照构建日志。
- `xsim.log`：运行期日志与 `TEST_PASS`/`TEST_FAIL` 证据。
- `xsim.dir\<snapshot>\xsimkernel.log`：内核加载与运行信息。

报告仿真结果时，应同时给出所运行的顶层、快照名称、三阶段退出码，以及 `TEST_PASS` 或首个 `ERROR` 的原文。

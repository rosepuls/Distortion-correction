param([string]$VivadoHome = $env:VIVADO_HOME, [switch]$FullFrame)
$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
$simDir = $PSScriptRoot
$rtl = [System.IO.Path]::GetFullPath((Join-Path $simDir '..\rtl\memory\frame_copy_engine.v'))
$tb = Join-Path $simDir 'frame_copy_engine_tb.v'
$faultTb = Join-Path $simDir 'frame_copy_engine_fault_tb.v'
$workDir = Join-Path $simDir ('.work\frame_copy_engine-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
Push-Location $workDir
try {
    if ($FullFrame) {
        & $xvlog --sv -d FULL_FRAME --work work --log xvlog.log $rtl $tb $faultTb
    } else {
        & $xvlog --sv --work work --log xvlog.log $rtl $tb $faultTb
    }
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.frame_copy_engine_tb -s frame_copy_engine_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim frame_copy_engine_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed.' }
    if ((Select-String -LiteralPath xsim.log -Pattern 'FATAL_ERROR|FAIL' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: frame_copy_engine .* words equal and drained' -Quiet)) {
        throw 'Frame-copy engine testbench did not report PASS.'
    }
    & $xelab work.frame_copy_engine_fault_tb -s frame_copy_engine_fault_tb_sim --log fault-xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'fault xelab failed.' }
    & $xsim frame_copy_engine_fault_tb_sim -runall --log fault-xsim.log
    if ($LASTEXITCODE -ne 0) { throw 'fault xsim failed.' }
    if ((Select-String -LiteralPath fault-xsim.log -Pattern 'FATAL_ERROR|FAIL' -Quiet) -or
        -not (Select-String -LiteralPath fault-xsim.log -Pattern 'PASS: frame_copy_engine short read aborts' -Quiet)) {
        throw 'Frame-copy fault testbench did not report PASS.'
    }
} finally { Pop-Location }

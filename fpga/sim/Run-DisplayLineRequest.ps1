param([string]$VivadoHome = $env:VIVADO_HOME)
$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
$simDir = $PSScriptRoot
$rtl = [System.IO.Path]::GetFullPath((Join-Path $simDir '..\project\stage3_dual_pool_copy\source\rtl\rd_buf.v'))
$tb = Join-Path $simDir 'display_line_request_tb.v'
$workDir = Join-Path $simDir ('.work\display_line_request-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
Push-Location $workDir
try {
    & $xvlog --sv --work work --log xvlog.log $rtl $tb
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.display_line_request_tb -s display_line_request_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim display_line_request_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed.' }
    if ((Select-String -LiteralPath xsim.log -Pattern 'FATAL_ERROR|FAIL' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: rd_buf line request holds' -Quiet)) {
        throw 'Display-line request testbench did not report PASS.'
    }
} finally { Pop-Location }

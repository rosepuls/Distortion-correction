param([string]$VivadoHome = $env:VIVADO_HOME)
$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
$simDir = $PSScriptRoot
$rtlDir = [System.IO.Path]::GetFullPath((Join-Path $simDir '..\rtl\memory'))
$rtl = @('frame_pool_manager.v','frame_pipeline_ownership.v',
    'frame_copy_engine.v','ddr_read_burst_arbiter.v',
    'ddr_write_burst_arbiter.v','ddr_write_drain_tracker.v') |
    ForEach-Object { Join-Path $rtlDir $_ }
$tb = Join-Path $simDir 'four_client_ddr_integration_tb.v'
$workDir = Join-Path $simDir ('.work\four_client_ddr-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
Push-Location $workDir
try {
    & $xvlog --sv --work work --log xvlog.log $rtl $tb
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.four_client_ddr_integration_tb -s four_client_ddr_integration_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim four_client_ddr_integration_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed.' }
    if ((Select-String -LiteralPath xsim.log -Pattern 'FATAL_ERROR|FAIL' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: four-client DDR arbitration' -Quiet)) {
        throw 'Four-client integration testbench did not report PASS.'
    }
} finally { Pop-Location }

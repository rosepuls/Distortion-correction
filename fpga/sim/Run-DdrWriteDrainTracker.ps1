param(
    [string]$VivadoHome = $env:VIVADO_HOME
)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) {
    throw 'Set VIVADO_HOME or pass -VivadoHome to locate Vivado Simulator.'
}
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Vivado Simulator tool not found: $tool"
    }
}

$source = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\rtl\memory\ddr_write_drain_tracker.v'))
$testbench = Join-Path $PSScriptRoot 'ddr_write_drain_tracker_tb.v'
$workDir = Join-Path $PSScriptRoot ('.work\ddr_write_drain_tracker-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

Push-Location $workDir
try {
    & $xvlog --work work --log xvlog.log $source $testbench
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.ddr_write_drain_tracker_tb -s ddr_write_drain_tracker_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim ddr_write_drain_tracker_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed.' }
    if ((Select-String -LiteralPath xsim.log -Pattern 'FATAL_ERROR|FAIL' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: ddr_write_drain_tracker ownership and fault test' -Quiet)) {
        throw 'Write drain tracker testbench did not report PASS.'
    }
} finally {
    Pop-Location
}

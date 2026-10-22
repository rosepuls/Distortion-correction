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

$simDir = $PSScriptRoot
$manager = [System.IO.Path]::GetFullPath((Join-Path $simDir '..\rtl\memory\frame_pool_manager.v'))
$ownership = [System.IO.Path]::GetFullPath((Join-Path $simDir '..\rtl\memory\frame_pipeline_ownership.v'))
$testbench = Join-Path $simDir 'frame_pipeline_ownership_tb.v'
$workDir = Join-Path $simDir ('.work\frame_pipeline_ownership-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

Push-Location $workDir
try {
    & $xvlog --sv --work work --log xvlog.log $manager $ownership $testbench
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.frame_pipeline_ownership_tb -s frame_pipeline_ownership_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim frame_pipeline_ownership_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed.' }
    if ((Select-String -LiteralPath xsim.log -Pattern 'FATAL_ERROR|FAIL:' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: frame_pipeline_ownership two-pool handoff test' -Quiet)) {
        throw 'Ownership testbench did not report PASS.'
    }
} finally {
    Pop-Location
}

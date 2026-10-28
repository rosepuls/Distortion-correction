param([string]$VivadoHome = $env:VIVADO_HOME)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) {
    throw 'Set VIVADO_HOME or pass -VivadoHome to locate Vivado Simulator.'
}

$simDir = $PSScriptRoot
$projectRoot = Split-Path $simDir -Parent
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Vivado Simulator tool not found: $tool"
    }
}

$workDir = Join-Path $simDir ('.work\stage9-bicubic-planner-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
$rtl = Join-Path $projectRoot 'source\rtl\correction\bicubic_sample_planner.sv'
$testbench = Join-Path $simDir 'bicubic_sample_planner_tb.sv'

Push-Location $workDir
try {
    & $xvlog --sv --work work --log xvlog.log $rtl $testbench
    if ($LASTEXITCODE -ne 0) { throw 'Stage 9 planner xvlog failed.' }
    & $xelab work.bicubic_sample_planner_tb -s stage9_bicubic_planner_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'Stage 9 planner xelab failed.' }
    & $xsim stage9_bicubic_planner_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: Stage 9 bicubic stencil, strict border and handshake test' -Quiet)) {
        throw 'Stage 9 planner simulation did not report PASS.'
    }
} finally {
    Pop-Location
}

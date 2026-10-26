param([string]$VivadoHome = $env:VIVADO_HOME)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) {
    throw 'Set VIVADO_HOME or pass -VivadoHome to locate Vivado Simulator.'
}

$simDir = $PSScriptRoot
$projectRoot = Split-Path $simDir -Parent
$rtl = Join-Path $projectRoot 'source\rtl\correction\pipelined_catmull_rom_interpolator.sv'
$testbench = Join-Path $simDir 'catmull_rom_interpolator_tb.sv'
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Vivado Simulator tool not found: $tool"
    }
}

$workDir = Join-Path $simDir ('.work\stage9-catmull-rom-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
Push-Location $workDir
try {
    & $xvlog --sv --work work --log xvlog.log $rtl $testbench
    if ($LASTEXITCODE -ne 0) { throw 'Catmull-Rom interpolator xvlog failed.' }
    & $xelab work.catmull_rom_interpolator_tb -s stage9_catmull_rom_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'Catmull-Rom interpolator xelab failed.' }
    & $xsim stage9_catmull_rom_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: Stage 9 Catmull-Rom fixed-point, saturation and elastic metadata test' -Quiet)) {
        throw 'Catmull-Rom interpolator simulation did not report PASS.'
    }
} finally {
    Pop-Location
}

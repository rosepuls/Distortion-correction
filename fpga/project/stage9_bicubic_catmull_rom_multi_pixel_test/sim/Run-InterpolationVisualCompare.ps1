param(
    [string]$VivadoHome = $env:VIVADO_HOME,
    [string]$Stage8Project = (Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) 'stage8_brown_y_mul_fix_test')
)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
$projectRoot = Split-Path $PSScriptRoot -Parent
$stage8Rtl = Join-Path $Stage8Project 'source\rtl\correction\pipelined_bilinear_interpolator.sv'
$stage9BilinearRtl = Join-Path $projectRoot 'source\rtl\correction\pipelined_bilinear_interpolator.sv'
$stage9BicubicRtl = Join-Path $projectRoot 'source\rtl\correction\pipelined_catmull_rom_interpolator.sv'
$testbench = Join-Path $PSScriptRoot 'interpolation_visual_tb.sv'
$outDir = Join-Path $PSScriptRoot 'comparison_output'
$workRoot = Join-Path $PSScriptRoot '.work\interpolation-visual'
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($path in @($stage8Rtl, $stage9BilinearRtl, $stage9BicubicRtl, $testbench, $xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required file: $path" }
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

function Invoke-InterpolationSimulation([string]$Name, [string]$Rtl, [bool]$Bicubic) {
    $work = Join-Path $workRoot ($Name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    Push-Location $work
    try {
        if ($Bicubic) {
            & $xvlog --sv --work work -d BICUBIC --log xvlog.log $Rtl $testbench
        } else {
            & $xvlog --sv --work work --log xvlog.log $Rtl $testbench
        }
        if ($LASTEXITCODE -ne 0) { throw "$Name xvlog failed." }
        & $xelab work.interpolation_visual_tb -s "${Name}_sim" --log xelab.log
        if ($LASTEXITCODE -ne 0) { throw "$Name xelab failed." }
        & $xsim "${Name}_sim" -runall --log xsim.log
        if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: RTL' -Quiet)) {
            throw "$Name simulation did not report PASS."
        }
        Copy-Item -LiteralPath 'pixels.csv' -Destination (Join-Path $outDir "$Name.csv") -Force
    } finally { Pop-Location }
}

Invoke-InterpolationSimulation 'stage8_bilinear' $stage8Rtl $false
Invoke-InterpolationSimulation 'stage9_catmull_rom' $stage9BicubicRtl $true
Write-Output "PASS: Both project RTL simulations generated 128x128 pixel captures in $outDir"

param(
    [string]$VivadoHome = $env:VIVADO_HOME,
    [string]$Stage8Project = (Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) 'stage8_brown_y_mul_fix_test')
)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$stage8Rtl = Join-Path $Stage8Project 'source\rtl\correction\pipelined_bilinear_interpolator.sv'
$stage9Rtl = Join-Path $projectRoot 'source\rtl\correction\pipelined_catmull_rom_interpolator.sv'
$testbench = Join-Path $PSScriptRoot 'interpolation_720p_tb.sv'
$chartGenerator = Join-Path $PSScriptRoot 'generate_color_chart.py'
$renderer = Join-Path $PSScriptRoot 'render_720p_comparison.py'
$outDir = Join-Path $PSScriptRoot 'output'
$workRoot = Join-Path $PSScriptRoot '.work'
$python = (Get-Command python -ErrorAction Stop).Source
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($path in @($stage8Rtl, $stage9Rtl, $testbench, $chartGenerator, $renderer, $xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required file: $path" }
}

New-Item -ItemType Directory -Path $outDir -Force | Out-Null
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
& $python $chartGenerator
if ($LASTEXITCODE -ne 0) { throw 'Test chart generation failed.' }

function Invoke-InterpolationSimulation([string]$Name, [string]$Rtl, [bool]$Bicubic) {
    $work = Join-Path $workRoot ($Name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'source_rgb.mem') -Destination (Join-Path $work 'source_rgb.mem')
    Push-Location $work
    try {
        if ($Bicubic) {
            & $xvlog --sv --work work -d BICUBIC --log xvlog.log $Rtl $testbench
        } else {
            & $xvlog --sv --work work --log xvlog.log $Rtl $testbench
        }
        if ($LASTEXITCODE -ne 0) { throw "$Name xvlog failed." }
        & $xelab work.interpolation_720p_tb -s "${Name}_sim" --log xelab.log
        if ($LASTEXITCODE -ne 0) { throw "$Name xelab failed." }
        & $xsim "${Name}_sim" -runall --log xsim.log
        if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: 720p' -Quiet)) {
            throw "$Name simulation did not report PASS. See $work\xsim.log"
        }
        Copy-Item -LiteralPath 'pixels_rgb.hex' -Destination (Join-Path $outDir "$Name.hex") -Force
    } finally { Pop-Location }
}

Invoke-InterpolationSimulation 'stage8_bilinear' $stage8Rtl $false
Invoke-InterpolationSimulation 'stage9_catmull_rom' $stage9Rtl $true
& $python $renderer
if ($LASTEXITCODE -ne 0) { throw 'Comparison rendering failed.' }
Write-Output "PASS: exact Stage 8 bilinear and Stage 9 Catmull-Rom RTL simulated 921600 same-coordinate pixels. Results: $outDir"

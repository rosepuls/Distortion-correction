param([string]$ModelSimBin = 'D:\modeltech64_10.6e\win64')

$ErrorActionPreference = 'Stop'
$vlog = Join-Path $ModelSimBin 'vlog.exe'
$vsim = Join-Path $ModelSimBin 'vsim.exe'
foreach ($tool in @($vlog, $vsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing simulator tool: $tool" }
}

$project = Split-Path -Parent $PSScriptRoot
$rtl = @(
    (Join-Path $project 'source\rtl\sr\sr_luma_line_ram.sv'),
    (Join-Path $project 'source\rtl\sr\sr_luma_window3x3.sv')
)
$tb = Join-Path $PSScriptRoot 'sr_luma_window3x3_tb.sv'
$work = Join-Path $PSScriptRoot '.work\sr-luma-window'
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & $vlog -sv -work work @rtl $tb
    if ($LASTEXITCODE -ne 0) { throw 'ModelSim compile failed.' }
    & $vsim -c work.sr_luma_window3x3_tb -do 'run -all; quit -f'
    if ($LASTEXITCODE -ne 0) { throw 'ModelSim simulation failed.' }
} finally { Pop-Location }

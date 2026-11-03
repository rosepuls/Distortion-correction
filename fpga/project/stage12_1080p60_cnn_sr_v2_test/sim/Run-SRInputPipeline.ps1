param([string]$ModelSimBin = 'D:\modeltech64_10.6e\win64')
$ErrorActionPreference = 'Stop'
$vlog = Join-Path $ModelSimBin 'vlog.exe'
$vsim = Join-Path $ModelSimBin 'vsim.exe'
foreach ($tool in @($vlog, $vsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing simulator tool: $tool" }
}
$project = Split-Path -Parent $PSScriptRoot
$rtl = @(
    (Join-Path $project 'source\rtl\sr\sr_source_dma.sv'),
    (Join-Path $project 'source\rtl\sr\sr_luma_frontend.sv'),
    (Join-Path $project 'source\rtl\sr\sr_luma_line_ram.sv'),
    (Join-Path $project 'source\rtl\sr\sr_luma_window3x3.sv'),
    (Join-Path $project 'source\rtl\sr\sr_input_pipeline.sv')
)
$tb = Join-Path $PSScriptRoot 'sr_input_pipeline_tb.sv'
$work = Join-Path $PSScriptRoot '.work\sr-input-pipeline'
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & $vlog -sv -work work @rtl $tb
    if ($LASTEXITCODE -ne 0) { throw 'ModelSim compile failed.' }
    $simulationOutput = & $vsim -c work.sr_input_pipeline_tb -do 'run -all; quit -f' 2>&1
    $simulationOutput | Write-Output
    if ($LASTEXITCODE -ne 0 -or -not ($simulationOutput -match 'PASS:') -or
        ($simulationOutput -match '\*\* Fatal:')) {
        throw 'ModelSim simulation failed or did not reach the PASS marker.'
    }
} finally { Pop-Location }

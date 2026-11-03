param([string]$ModelSimBin = 'D:\modeltech64_10.6e\win64')
$ErrorActionPreference = 'Stop'
$vlog = Join-Path $ModelSimBin 'vlog.exe'
$vsim = Join-Path $ModelSimBin 'vsim.exe'
foreach ($tool in @($vlog, $vsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing simulator tool: $tool" }
}
$project = Split-Path -Parent $PSScriptRoot
$includeDir = $project
$rtl = @(
    (Join-Path $project 'source\rtl\sr\sr_stem_conv.sv'),
    (Join-Path $project 'source\rtl\sr\sr_feature_fifo4.sv'),
    (Join-Path $project 'source\rtl\sr\sr_feature_line_ram.sv'),
    (Join-Path $project 'source\rtl\sr\sr_feature_window3x3.sv'),
    (Join-Path $project 'source\rtl\sr\sr_feature_halo.sv'),
    (Join-Path $project 'source\rtl\sr\sr_feature_window_pipeline.sv'),
    (Join-Path $project 'source\rtl\sr\sr_window_fifo1.sv'),
    (Join-Path $project 'source\rtl\sr\sr_depthwise_conv.sv'),
    (Join-Path $project 'source\rtl\sr\sr_pointwise_conv.sv'),
    (Join-Path $project 'source\rtl\sr\sr_feature_result_fifo2.sv'),
    (Join-Path $project 'source\rtl\sr\sr_residual_join.sv'),
    (Join-Path $project 'source\rtl\sr\sr_stem_depthwise_chain.sv')
)
$tb = Join-Path $PSScriptRoot 'sr_stem_depthwise_chain_tb.sv'
$work = Join-Path $PSScriptRoot '.work\sr-stem-depthwise-chain'
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & $vlog -sv -work work "+incdir+$includeDir" $rtl $tb
    if ($LASTEXITCODE -ne 0) { throw 'ModelSim compile failed.' }
    $simulationOutput = & $vsim -c work.sr_stem_depthwise_chain_tb -do 'run -all; quit -f' 2>&1
    $simulationOutput | Write-Output
    if ($LASTEXITCODE -ne 0 -or -not ($simulationOutput -match 'PASS:') -or
        ($simulationOutput -match '\*\* Fatal:')) {
        throw 'ModelSim simulation failed or did not reach the PASS marker.'
    }
} finally { Pop-Location }

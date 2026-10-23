param([string]$VivadoHome = $env:VIVADO_HOME)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing Vivado tool: $tool" }
}
$work = Join-Path $PSScriptRoot '.work\stage7-cache-replay'
New-Item -ItemType Directory -Path $work -Force | Out-Null
$mapper = Join-Path $PSScriptRoot '..\rtl\correction\stage6_brown_mapper.sv'
$planner = Join-Path $PSScriptRoot '..\rtl\correction\bilinear_sample_planner.sv'
$bench = Join-Path $PSScriptRoot 'stage7_cache_trace_tb.sv'
Push-Location $work
try {
    & $xvlog --sv --work work --log xvlog.log $mapper $planner $bench
    if ($LASTEXITCODE -ne 0) { throw 'Stage 7 trace xvlog failed.' }
    & $xelab work.stage7_cache_trace_tb -s stage7_cache_trace_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'Stage 7 trace xelab failed.' }
    & $xsim stage7_cache_trace_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: exported 921600 fixed-point Stage 7 cache coordinates' -Quiet)) {
        throw 'Stage 7 coordinate export failed.'
    }
    & python (Join-Path $PSScriptRoot 'stage7_cache_replay.py') 'stage7_tile_trace.csv' |
        Set-Content -LiteralPath 'stage7_cache_replay.json' -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw 'Stage 7 cache replay failed.' }
    Get-Content -LiteralPath 'stage7_cache_replay.json'
} finally {
    Pop-Location
}

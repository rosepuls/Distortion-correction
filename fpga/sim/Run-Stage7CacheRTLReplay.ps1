param(
    [string]$VivadoHome = $env:VIVADO_HOME,
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot '..\project\stage7_read_pipeline_16x8'),
    [switch]$ExpectFrameLruReset
)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing Vivado tool: $tool" }
}
$work = Join-Path $PSScriptRoot '.work\stage7-cache-replay'
if (-not (Test-Path -LiteralPath (Join-Path $work 'stage7_tile_trace.csv') -PathType Leaf)) {
    throw 'Coordinate trace missing; run Run-Stage7CacheReplay.ps1 first.'
}
$projectCache = Join-Path $ProjectDirectory 'source\rtl\memory\pixel_tile_cache.sv'
if (-not (Test-Path -LiteralPath $projectCache -PathType Leaf)) {
    throw "Project cache missing: $projectCache"
}
$projectCache = (Resolve-Path -LiteralPath $projectCache).Path
$sources = @(
    (Join-Path (Split-Path $projectCache) 'tile_cache_bank_ram.sv'),
    $projectCache,
    (Join-Path $PSScriptRoot 'stage7_cache_rtl_replay_tb.sv')
)
Push-Location $work
try {
    $modelArgs = @('stage7_tile_trace.csv', '--frames', '5',
        '--miss-trace', 'stage7_model_misses.csv')
    if (-not $ExpectFrameLruReset) { $modelArgs += '--preserve-lru-between-frames' }
    & python (Join-Path $PSScriptRoot 'stage7_cache_replay.py') @modelArgs |
        Set-Content -LiteralPath 'stage7_cache_replay.json' -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw 'Python cache model replay failed.' }
    & $xvlog --sv --work work --log xvlog_cache.log @sources
    if ($LASTEXITCODE -ne 0) { throw 'RTL cache replay xvlog failed.' }
    & $xelab work.stage7_cache_rtl_replay_tb -s stage7_cache_rtl_replay_sim --log xelab_cache.log
    if ($LASTEXITCODE -ne 0) { throw 'RTL cache replay xelab failed.' }
    & $xsim stage7_cache_rtl_replay_sim -runall --log xsim_cache.log
    if ($LASTEXITCODE -ne 0 -or
        -not (Select-String -LiteralPath xsim_cache.log -Pattern 'PASS: Stage 7 RTL replay frames=5 pixels_per_frame=921600' -Quiet)) {
        throw 'RTL cache replay failed.'
    }
    & python (Join-Path $PSScriptRoot 'Compare-Stage7CacheMissTrace.py') `
        'stage7_model_misses.csv' 'stage7_rtl_misses.csv'
    if ($LASTEXITCODE -ne 0) { throw 'Cache model and RTL miss traces differ.' }
} finally {
    Pop-Location
}

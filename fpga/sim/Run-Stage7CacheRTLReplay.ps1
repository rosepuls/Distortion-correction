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
if (-not (Test-Path -LiteralPath (Join-Path $work 'stage7_tile_trace.csv') -PathType Leaf)) {
    throw 'Coordinate trace missing; run Run-Stage7CacheReplay.ps1 first.'
}
$memory = Join-Path $PSScriptRoot '..\rtl\memory'
$sources = @(
    (Join-Path $memory 'tile_cache_bank_ram.sv'),
    (Join-Path $memory 'pixel_tile_cache.sv'),
    (Join-Path $PSScriptRoot 'stage7_cache_rtl_replay_tb.sv')
)
Push-Location $work
try {
    & $xvlog --sv --work work --log xvlog_cache.log @sources
    if ($LASTEXITCODE -ne 0) { throw 'RTL cache replay xvlog failed.' }
    & $xelab work.stage7_cache_rtl_replay_tb -s stage7_cache_rtl_replay_sim --log xelab_cache.log
    if ($LASTEXITCODE -ne 0) { throw 'RTL cache replay xelab failed.' }
    & $xsim stage7_cache_rtl_replay_sim -runall --log xsim_cache.log
    if ($LASTEXITCODE -ne 0 -or
        -not (Select-String -LiteralPath xsim_cache.log -Pattern 'PASS: Stage 7 RTL replay pixels=921600' -Quiet)) {
        throw 'RTL cache replay failed.'
    }
} finally {
    Pop-Location
}

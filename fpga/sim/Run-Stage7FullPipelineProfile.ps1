param(
    [int]$CacheSets = 16,
    [int]$CacheWays = 4,
    [int]$ReadDelay = 2,
    [int]$WritePause = 0,
    [string]$VivadoHome = $env:VIVADO_HOME
)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
if ($CacheSets -notin @(16,32) -or $CacheWays -notin @(4,8)) {
    throw 'Use CacheSets=16/32 and CacheWays=4/8.'
}
if ($ReadDelay -lt 0 -or $ReadDelay -gt 255) { throw 'ReadDelay must be between 0 and 255.' }
if ($WritePause -lt 0 -or $WritePause -gt 255) { throw 'WritePause must be between 0 and 255.' }
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing Vivado tool: $tool" }
}
$work = Join-Path $PSScriptRoot ".work\stage7-full-${CacheSets}x${CacheWays}-delay${ReadDelay}-pause${WritePause}"
New-Item -ItemType Directory -Path $work -Force | Out-Null
$memory = Join-Path $PSScriptRoot '..\rtl\memory'
$correction = Join-Path $PSScriptRoot '..\rtl\correction'
$sources = @(
    (Join-Path $memory 'tile_cache_bank_ram.sv'),
    (Join-Path $memory 'pixel_tile_cache.sv'),
    (Join-Path $memory 'tile_row_ddr_adapter.sv'),
    (Join-Path $memory 'cached_neighbor_reader.sv'),
    (Join-Path $correction 'identity_mapper.sv'),
    (Join-Path $correction 'stage6_brown_mapper.sv'),
    (Join-Path $correction 'coordinate_fifo.sv'),
    (Join-Path $correction 'identity_coordinate_pipeline.sv'),
    (Join-Path $correction 'bilinear_sample_planner.sv'),
    (Join-Path $correction 'pipelined_bilinear_interpolator.sv'),
    (Join-Path $correction 'stage5_identity_pipeline.sv'),
    (Join-Path $PSScriptRoot 'stage7_full_pipeline_profile_tb.sv')
)
Push-Location $work
try {
    & $xvlog --sv --work work --log xvlog.log @sources
    if ($LASTEXITCODE -ne 0) { throw 'Stage 7 full pipeline xvlog failed.' }
    $setArg = '"CACHE_SETS=' + $CacheSets + '"'
    $wayArg = '"CACHE_WAYS=' + $CacheWays + '"'
    $delayArg = '"READ_DELAY=' + $ReadDelay + '"'
    $pauseArg = '"WRITE_PAUSE=' + $WritePause + '"'
    & $xelab work.stage7_full_pipeline_profile_tb -generic_top $setArg -generic_top $wayArg -generic_top $delayArg -generic_top $pauseArg -s stage7_full_pipeline_profile_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'Stage 7 full pipeline xelab failed.' }
    & $xsim stage7_full_pipeline_profile_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: Stage 7 full pipeline' -Quiet)) {
        throw 'Stage 7 full pipeline profile failed.'
    }
} finally {
    Pop-Location
}

param(
    [string]$VivadoHome = $env:VIVADO_HOME,
    [int]$CacheSets = 16,
    [int]$CacheWays = 4
)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing Vivado tool: $tool" }
}
$memory = Join-Path $PSScriptRoot '..\rtl\memory'
$correction = Join-Path $PSScriptRoot '..\rtl\correction'
$sources = @(
    (Join-Path $memory 'tile_cache_bank_ram.sv'),
    (Join-Path $memory 'pixel_tile_cache.sv'),
    (Join-Path $memory 'tile_row_ddr_adapter.sv'),
    (Join-Path $memory 'cached_neighbor_reader.sv'),
    (Join-Path $correction 'identity_mapper.sv'),
    (Join-Path $PSScriptRoot '..\project\stage6_radial_ddr\source\rtl\correction\demo_radial_mapper.sv'),
    (Join-Path $correction 'coordinate_fifo.sv'),
    (Join-Path $correction 'identity_coordinate_pipeline.sv'),
    (Join-Path $correction 'bilinear_sample_planner.sv'),
    (Join-Path $correction 'pipelined_bilinear_interpolator.sv'),
    (Join-Path $correction 'stage5_identity_pipeline.sv'),
    (Join-Path $PSScriptRoot 'stage6_radial_pipeline_tb.sv')
)
$work = Join-Path $PSScriptRoot ('.work\stage6-radial-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & $xvlog --sv --work work --log xvlog.log @sources
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    $setArg = '"CACHE_SETS=' + $CacheSets + '"'
    $wayArg = '"CACHE_WAYS=' + $CacheWays + '"'
    & $xelab work.stage6_radial_pipeline_tb -generic_top $setArg -generic_top $wayArg -s stage6_radial_pipeline_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim stage6_radial_pipeline_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        (Select-String -LiteralPath xsim.log -Pattern 'FAIL' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: Stage 6 Brown mapping sampled DDR pixels and preserved metadata' -Quiet)) {
        throw 'Stage 6 radial pipeline simulation did not report PASS.'
    }
} finally { Pop-Location }

param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot '..\project\stage7_write_overlap_16x8'),
    [string]$VivadoHome = $env:VIVADO_HOME,
    [switch]$FullFrame,
    [switch]$Fault
)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
if (-not (Test-Path -LiteralPath $ProjectDirectory -PathType Container)) {
    throw "Project missing: $ProjectDirectory"
}
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing Vivado tool: $tool" }
}
$rtl = Join-Path $ProjectDirectory 'source\rtl'
$memory = Join-Path $rtl 'memory'
$correction = Join-Path $rtl 'correction'
$sources = @(
    (Join-Path $memory 'tile_cache_bank_ram.sv'),
    (Join-Path $memory 'pixel_tile_cache.sv'),
    (Join-Path $memory 'tile_row_ddr_adapter.sv'),
    (Join-Path $memory 'cached_neighbor_reader.sv'),
    (Join-Path $correction 'identity_mapper.sv'),
    (Join-Path $correction 'demo_radial_mapper.sv'),
    (Join-Path $correction 'coordinate_fifo.sv'),
    (Join-Path $correction 'identity_coordinate_pipeline.sv'),
    (Join-Path $correction 'bilinear_sample_planner.sv'),
    (Join-Path $correction 'pipelined_bilinear_interpolator.sv'),
    (Join-Path $correction 'stage5_identity_pipeline.sv'),
    (Join-Path $memory 'frame_identity_transform_engine.sv'),
    (Join-Path $PSScriptRoot 'stage7_write_overlap_tb.sv')
)
$work = Join-Path $PSScriptRoot ('.work\stage7-write-overlap-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    $defineArgs = if ($FullFrame) { @('--define', 'FULL_FRAME_TEST') } else { @() }
    if ($Fault) { $defineArgs += @('--define', 'BAD_WLAST') }
    & $xvlog --sv --work work --log xvlog.log @defineArgs @sources
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.stage7_write_overlap_tb -s stage7_write_overlap_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim stage7_write_overlap_tb_sim -runall --log xsim.log
    $passPattern = if ($Fault) {
        'PASS: malformed WLAST rejects output publication'
    } elseif ($FullFrame) {
        'PASS: full 1280x720 DDR identity frame'
    } else {
        'PASS: two ping-pong frames preserve DDR data'
    }
    if ($LASTEXITCODE -ne 0 -or
        (Select-String -LiteralPath xsim.log -Pattern 'FAIL' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern $passPattern -Quiet)) {
        throw "Write-overlap behavior failed: $work"
    }
    Write-Host "PASS: write-overlap behavior verified: $work"
} finally { Pop-Location }

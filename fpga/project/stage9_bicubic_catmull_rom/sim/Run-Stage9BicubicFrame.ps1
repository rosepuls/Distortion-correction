param(
    [string]$VivadoHome = $env:VIVADO_HOME,
    [switch]$FullHd,
    [switch]$Bilinear
)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) {
    throw 'Set VIVADO_HOME or pass -VivadoHome to locate Vivado Simulator.'
}

$simDir = $PSScriptRoot
$projectRoot = Split-Path $simDir -Parent
$rtl = Join-Path $projectRoot 'source\rtl'
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Vivado Simulator tool not found: $tool"
    }
}

$sources = @(
    (Join-Path $rtl 'memory\tile_cache_bank_ram.sv'),
    (Join-Path $rtl 'memory\pixel_tile_cache.sv'),
    (Join-Path $rtl 'memory\tile_row_ddr_adapter.sv'),
    (Join-Path $rtl 'memory\cached_bicubic_neighbor_reader.sv'),
    (Join-Path $rtl 'memory\cached_neighbor_reader.sv'),
    (Join-Path $rtl 'correction\identity_mapper.sv'),
    (Join-Path $rtl 'correction\coordinate_fifo.sv'),
    (Join-Path $rtl 'correction\identity_coordinate_pipeline.sv'),
    (Join-Path $rtl 'correction\bicubic_sample_planner.sv'),
    (Join-Path $rtl 'correction\bilinear_sample_planner.sv'),
    (Join-Path $rtl 'correction\pipelined_catmull_rom_interpolator.sv'),
    (Join-Path $rtl 'correction\pipelined_bilinear_interpolator.sv'),
    (Join-Path $rtl 'correction\stage5_identity_pipeline.sv'),
    (Join-Path $simDir 'stage9_bicubic_frame_tb.sv')
)
$work = Join-Path $simDir ('.work\stage9-bicubic-frame-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    $xvlogArgs = @('--sv', '-i', $projectRoot, '--work', 'work', '--log', 'xvlog.log')
    if ($FullHd) { $xvlogArgs += @('-d', 'STAGE9_FULL_HD') }
    if ($Bilinear) { $xvlogArgs += @('-d', 'STAGE9_USE_BILINEAR') }
    & $xvlog @xvlogArgs @sources
    if ($LASTEXITCODE -ne 0) { throw 'Stage 9 frame xvlog failed.' }
    & $xelab work.stage9_bicubic_frame_tb -s stage9_bicubic_frame_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'Stage 9 frame xelab failed.' }
    & $xsim stage9_bicubic_frame_sim -runall --log xsim.log
    $size = if ($FullHd) { '1280x720' } else { '64x8' }
    $mode = if ($Bilinear) { 'bilinear' } else { 'bicubic' }
    $expectedPass = "PASS: Stage 9 complete $size $mode identity frame and strict borders"
    if ($LASTEXITCODE -ne 0 -or
        -not (Select-String -LiteralPath xsim.log -Pattern $expectedPass -Quiet)) {
        throw 'Stage 9 frame simulation did not report PASS.'
    }
} finally {
    Pop-Location
}

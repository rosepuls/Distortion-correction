param([string]$VivadoHome = $env:VIVADO_HOME)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing Vivado tool: $tool" }
}

$project = Split-Path -Parent $PSScriptRoot
$rtl = Join-Path $project 'source\rtl'
$sources = @(
    "$rtl\correction\coordinate_fifo.sv",
    "$rtl\correction\scale_3_2_mapper.sv",
    "$rtl\correction\scale_3_2_coordinate_pipeline.sv",
    "$rtl\correction\bilinear_sample_planner.sv",
    "$rtl\correction\adaptive_bilinear_sharpener.sv",
    "$rtl\correction\stage12_super_resolution_pipeline.sv",
    "$rtl\memory\tile_cache_bank_ram.sv",
    "$rtl\memory\pixel_tile_cache.sv",
    "$rtl\memory\tile_row_ddr_adapter.sv",
    "$rtl\memory\cached_neighbor_reader.sv",
    "$rtl\memory\frame_identity_transform_engine.sv",
    (Join-Path $PSScriptRoot 'stage12_full_frame_tb.sv')
)
$work = Join-Path $PSScriptRoot '.work\stage12-full-frame'
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & $xvlog --sv --work work --log xvlog.log @sources
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.stage12_full_frame_tb -s stage12_full_frame_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim stage12_full_frame_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        (Select-String -LiteralPath xsim.log -Pattern 'FAIL' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: Stage 12 1080p frame pixels=2073600 bursts=16200' -Quiet)) {
        throw "Stage 12 full-frame simulation did not report PASS; inspect $(Join-Path $work 'xsim.log')"
    }
} finally {
    Pop-Location
}

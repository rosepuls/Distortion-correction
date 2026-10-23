param([string]$VivadoHome = $env:VIVADO_HOME, [switch]$Trace)

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
    (Join-Path $correction 'coordinate_fifo.sv'),
    (Join-Path $correction 'identity_coordinate_pipeline.sv'),
    (Join-Path $correction 'bilinear_sample_planner.sv'),
    (Join-Path $correction 'pipelined_bilinear_interpolator.sv'),
    (Join-Path $correction 'stage5_identity_pipeline.sv'),
    (Join-Path $PSScriptRoot 'stage5_identity_pipeline_tb.sv')
)
$work = Join-Path $PSScriptRoot ('.work\stage5-identity-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    $defineArgs = if ($Trace) { @('--define', 'TRACE_PIPELINE') } else { @() }
    & $xvlog --sv --work work --log xvlog.log @defineArgs @sources
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.stage5_identity_pipeline_tb -s stage5_identity_pipeline_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim stage5_identity_pipeline_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        (Select-String -LiteralPath xsim.log -Pattern 'FAIL' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: Stage 5 DDR-backed identity restored 1024 ordered pixels across two frames' -Quiet)) {
        throw 'Stage 5 identity simulation did not report PASS.'
    }
} finally { Pop-Location }

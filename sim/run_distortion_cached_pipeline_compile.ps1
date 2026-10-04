$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\distortion_cached_pipeline_compile'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot 'rtl\algorithm\distortion\coordinate_gen.sv') `
        (Join-Path $projectRoot 'rtl\algorithm\distortion\normalize.sv') `
        (Join-Path $projectRoot 'rtl\algorithm\distortion\coordinate_split.sv') `
        (Join-Path $projectRoot 'rtl\algorithm\distortion\distortion_core_optimized.sv') `
        (Join-Path $projectRoot 'rtl\algorithm\interpolation\bilinear_interp.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\coordinate_fifo.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\ddr_burst_reader.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\pixel_tile_cache.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\tile_cache_bank_ram.sv') `
        (Join-Path $projectRoot 'sim\pgl50h_tile_cache_bank_ip_model.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\cached_pixel_fetch_engine.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\control\algorithm_reset_tree.sv') `
        (Join-Path $projectRoot 'rtl\algorithm\distortion\distortion_image_pipeline.sv') `
        (Join-Path $projectRoot 'sim\tb_distortion_cached_pipeline_compile.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_distortion_cached_pipeline_compile -s distortion_cached_pipeline_compile_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & xsim distortion_cached_pipeline_compile_sim -runall 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: distortion_cached_pipeline_compile') {
        throw 'XSim completed without the expected cached pipeline compile pass marker.'
    }
}
finally {
    Pop-Location
}

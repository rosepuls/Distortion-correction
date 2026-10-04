$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\pgl50h_board_top_compile'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot 'sim\models\pgl50h_board_vendor_stubs.sv') `
        (Join-Path $projectRoot 'rtl\vendor\pgl50h\video\sync_vg.v') `
        (Join-Path $projectRoot 'rtl\algorithm\distortion\coordinate_gen.sv') `
        (Join-Path $projectRoot 'rtl\algorithm\distortion\normalize.sv') `
        (Join-Path $projectRoot 'rtl\algorithm\distortion\coordinate_split.sv') `
        (Join-Path $projectRoot 'rtl\algorithm\distortion\distortion_core.sv') `
        (Join-Path $projectRoot 'rtl\algorithm\distortion\distortion_core_optimized.sv') `
        (Join-Path $projectRoot 'rtl\algorithm\interpolation\bilinear_interp.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\pixel_fetch_engine.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\coordinate_fifo.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\pixel_tile_cache.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\tile_cache_bank_ram.sv') `
        (Join-Path $projectRoot 'sim\pgl50h_tile_cache_bank_ip_model.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\ddr_burst_reader.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\cached_pixel_fetch_engine.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\control\algorithm_reset_tree.sv') `
        (Join-Path $projectRoot 'rtl\algorithm\distortion\distortion_image_pipeline.sv') `
        (Join-Path $projectRoot 'rtl\board\pgl50h\clock_reset.sv') `
        (Join-Path $projectRoot 'rtl\board\pgl50h\mes50hp_top.sv') `
        (Join-Path $projectRoot 'rtl\board\pgl50h\ddr3_pixel_read_adapter.sv') `
        (Join-Path $projectRoot 'rtl\board\pgl50h\ddr3_rgbx_cache_adapter.sv') `
        (Join-Path $projectRoot 'rtl\board\pgl50h\algorithm_frame_writer.sv') `
        (Join-Path $projectRoot 'rtl\board\pgl50h\algorithm_frame_writer_rgbx.sv') `
        (Join-Path $projectRoot 'rtl\board\pgl50h\ddr3_frame_reader.sv') `
        (Join-Path $projectRoot 'rtl\board\pgl50h\ddr3_frame_reader_rgbx.sv') `
        (Join-Path $projectRoot 'rtl\board\pgl50h\board_video_control.sv') `
        (Join-Path $projectRoot 'rtl\board\pgl50h\video_mode_720p30.sv') `
        (Join-Path $projectRoot 'rtl\board\pgl50h\pgl50h_board_top.sv') `
        (Join-Path $projectRoot 'sim\tb_pgl50h_board_top_compile.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_pgl50h_board_top_compile -s pgl50h_board_top_compile_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & xsim pgl50h_board_top_compile_sim -runall 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: pgl50h_board_top_compile') {
        throw 'XSim completed without the expected pgl50h_board_top_compile pass marker.'
    }
}
finally {
    Pop-Location
}

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\pgl50h_board_top_compile'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot 'sim\models\pgl50h_board_vendor_stubs.sv') `
        (Join-Path $projectRoot 'rtl\vendor\mes50hp\video\sync_vg.v') `
        (Join-Path $projectRoot 'rtl\distortion\coordinate_gen.sv') `
        (Join-Path $projectRoot 'rtl\distortion\normalize.sv') `
        (Join-Path $projectRoot 'rtl\distortion\coordinate_split.sv') `
        (Join-Path $projectRoot 'rtl\distortion\distortion_core.sv') `
        (Join-Path $projectRoot 'rtl\distortion\distortion_core_optimized.sv') `
        (Join-Path $projectRoot 'rtl\interpolation\bilinear_interp.sv') `
        (Join-Path $projectRoot 'rtl\memory\pixel_fetch_engine.sv') `
        (Join-Path $projectRoot 'rtl\distortion\distortion_image_pipeline.sv') `
        (Join-Path $projectRoot 'rtl\board\mes50hp\clock_reset.sv') `
        (Join-Path $projectRoot 'rtl\board\mes50hp\mes50hp_top.sv') `
        (Join-Path $projectRoot 'rtl\board\mes50hp\ddr3_pixel_read_adapter.sv') `
        (Join-Path $projectRoot 'rtl\board\mes50hp\algorithm_frame_writer.sv') `
        (Join-Path $projectRoot 'rtl\board\mes50hp\ddr3_frame_reader.sv') `
        (Join-Path $projectRoot 'rtl\board\mes50hp\board_video_control.sv') `
        (Join-Path $projectRoot 'rtl\board\mes50hp\pgl50h_board_top.sv') `
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

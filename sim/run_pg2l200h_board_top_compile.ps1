$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$vivadoRoot = 'D:\Xilinx\Vivado\2020.2'
$runDirectory = Join-Path $projectRoot 'xsim.dir\pg2l200h_board_top_compile'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

$sources = @(
    'sim/models/pg2l200h_board_vendor_stubs.sv',
    'rtl/algorithm/distortion/coordinate_gen.sv',
    'rtl/algorithm/distortion/normalize.sv',
    'rtl/algorithm/distortion/coordinate_split.sv',
    'rtl/algorithm/distortion/distortion_core.sv',
    'rtl/algorithm/distortion/distortion_core_optimized.sv',
    'rtl/algorithm/interpolation/bilinear_interp.sv',
    'rtl/platform/common/memory/pixel_fetch_if.sv',
    'rtl/platform/common/memory/pixel_fetch_engine.sv',
    'rtl/platform/common/memory/coordinate_fifo.sv',
    'rtl/platform/common/memory/pixel_tile_cache.sv',
    'rtl/platform/common/memory/tile_cache_bank_ram.sv',
    'sim/tile_cache_bank_ip_model.sv',
    'rtl/platform/common/memory/ddr_burst_reader.sv',
    'rtl/platform/common/memory/cached_pixel_fetch_engine.sv',
    'rtl/platform/common/control/algorithm_reset_tree.sv',
    'rtl/algorithm/distortion/distortion_image_pipeline.sv',
    'rtl/board/pg2l200h/reset_sync.sv',
    'rtl/board/pg2l200h/distortion_frame_processor.sv',
    'rtl/board/pg2l200h/ddr3_pixel_read_adapter.sv',
    'rtl/board/pg2l200h/ddr3_rgbx_cache_adapter.sv',
    'rtl/board/pg2l200h/algorithm_frame_writer.sv',
    'rtl/board/pg2l200h/algorithm_frame_writer_rgbx.sv',
    'rtl/board/pg2l200h/ddr3_frame_reader.sv',
    'rtl/board/pg2l200h/ddr3_frame_reader_rgbx.sv',
    'rtl/board/pg2l200h/board_video_control.sv',
    'rtl/board/pg2l200h/realtime_frame_scheduler.sv',
    'rtl/board/pg2l200h/ddr_two_client_arbiter.sv',
    'rtl/board/pg2l200h/video_mode_720p60.sv',
    'rtl/board/pg2l200h/pg2l200h_board_top.sv',
    'sim/tb_pg2l200h_board_top_compile.sv'
) | ForEach-Object { Join-Path $projectRoot $_ }

Push-Location $runDirectory
try {
    & (Join-Path $vivadoRoot 'bin\xvlog.bat') -sv @sources
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & (Join-Path $vivadoRoot 'bin\xelab.bat') tb_pg2l200h_board_top_compile -s pg2l200h_board_top_compile_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & (Join-Path $vivadoRoot 'bin\xsim.bat') pg2l200h_board_top_compile_sim -R 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: pg2l200h_board_top_compile') {
        throw 'XSim completed without the expected PG2L200H board-top pass marker.'
    }
}
finally {
    Pop-Location
}

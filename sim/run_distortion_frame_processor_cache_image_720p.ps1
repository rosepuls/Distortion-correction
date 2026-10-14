<#
.SYNOPSIS
Runs the 1280x720 image correction through the 16-set x 4-way RGBX Tile Cache path.
#>

param(
    [ValidateSet(2, 4)]
    [int]$CacheWays = 4,

    [ValidateSet(16, 32)]
    [int]$CacheSets = 16
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$vivadoRoot = 'D:\Xilinx\Vivado\2020.2'
$resultDirectory = Join-Path $projectRoot "result\sim_assets\cache_full_chain_1280x720"
$runDirectory = Join-Path $projectRoot "xsim.dir\distortion_frame_processor_cache_image_1280x720"
$cleanPng = Join-Path $resultDirectory "clean_reference_1280x720.png"
$distortedPng = Join-Path $resultDirectory "distorted_input_1280x720.png"
$distortedMem = Join-Path $resultDirectory "distorted_input_rgb888_1280x720.mem"
$goldenPrefix = Join-Path $resultDirectory "corrected_q18_1280x720"
$goldenMem = Join-Path $resultDirectory "golden_corrected_q18_1280x720.mem"
$goldenPng = Join-Path $resultDirectory "golden_corrected_q18_1280x720.png"
$rtlMem = Join-Path $resultDirectory "rtl_corrected_q18_1280x720.mem"
$rtlPng = Join-Path $resultDirectory "rtl_corrected_q18_1280x720.png"
$panelPng = Join-Path $resultDirectory "cache_correction_comparison_1280x720.png"

New-Item -ItemType Directory -Force $resultDirectory | Out-Null
New-Item -ItemType Directory -Force $runDirectory | Out-Null

& py (Join-Path $projectRoot "software\sim_assets\create_checkerboard.py") `
    --width 1280 --height 720 --square-size 80 --color --output $cleanPng
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "software\sim_assets\generate_distorted_input.py") `
    $cleanPng --output $distortedPng `
    --fx 600.0 --fy 600.0 --cx 639.5 --cy 359.5 `
    --k1 -0.25 --k2 0.05 --p1 0.001 --p2 -0.001
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "software\sim_assets\image_to_mem.py") `
    $distortedPng --output $distortedMem
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "software\sim_assets\generate_distortion_vectors.py") `
    $distortedPng --output-prefix $goldenPrefix --optimized-q18 `
    --fx 600.0 --fy 600.0 --cx 639.5 --cy 359.5 `
    --k1 -0.25 --k2 0.05 --p1 0.001 --p2 -0.001
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Push-Location $runDirectory
try {
    & (Join-Path $vivadoRoot 'bin\xvlog.bat') -sv -d CACHE_IMAGE_720P -d "CACHE_WAYS_$CacheWays" -d "EXPECT_CACHE_WAYS_$CacheWays" `
        -d "TILE_CACHE_SETS_$CacheSets" `
        (Join-Path $projectRoot "rtl\algorithm\distortion\coordinate_gen.sv") `
        (Join-Path $projectRoot "rtl\algorithm\distortion\normalize.sv") `
        (Join-Path $projectRoot "rtl\algorithm\distortion\coordinate_split.sv") `
        (Join-Path $projectRoot "rtl\algorithm\distortion\distortion_core.sv") `
        (Join-Path $projectRoot "rtl\algorithm\distortion\distortion_core_optimized.sv") `
        (Join-Path $projectRoot "rtl\algorithm\interpolation\bilinear_interp.sv") `
        (Join-Path $projectRoot "rtl\platform\common\memory\coordinate_fifo.sv") `
        (Join-Path $projectRoot "rtl\platform\common\memory\ddr_burst_reader.sv") `
        (Join-Path $projectRoot "rtl\platform\common\memory\pixel_tile_cache.sv") `
        (Join-Path $projectRoot "rtl\platform\common\memory\tile_cache_bank_ram.sv") `
        (Join-Path $projectRoot "sim\tile_cache_bank_ip_model.sv") `
        (Join-Path $projectRoot "rtl\platform\common\memory\cached_pixel_fetch_engine.sv") `
        (Join-Path $projectRoot "rtl\platform\common\control\algorithm_reset_tree.sv") `
        (Join-Path $projectRoot "rtl\algorithm\distortion\distortion_image_pipeline.sv") `
        (Join-Path $projectRoot "rtl\board\pg2l200h\reset_sync.sv") `
        (Join-Path $projectRoot "rtl\board\pg2l200h\distortion_frame_processor.sv") `
        (Join-Path $projectRoot "sim\tb_distortion_frame_processor_cache_image.sv")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & (Join-Path $vivadoRoot 'bin\xelab.bat') tb_distortion_frame_processor_cache_image -s distortion_frame_processor_cache_image_720p_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $xsimOutput = & (Join-Path $vivadoRoot 'bin\xsim.bat') distortion_frame_processor_cache_image_720p_sim -R 2>&1
    $xsimExitCode = $LASTEXITCODE
    $xsimOutput | Write-Output
    if ($xsimExitCode -ne 0) { exit $xsimExitCode }
    if (($xsimOutput | Out-String) -notmatch "TEST_PASS: distortion_frame_processor_cache_image") {
        throw "XSim completed without the expected 720p cache image pass marker."
    }
}
finally {
    Pop-Location
}

& py (Join-Path $projectRoot "software\sim_assets\compare_mem_frames.py") `
    $goldenMem $rtlMem --width 1280 --height 720
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "result\tool\mem_to_png.py") `
    $goldenMem --width 1280 --height 720 --output $goldenPng
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "result\tool\mem_to_png.py") `
    $rtlMem --width 1280 --height 720 --output $rtlPng
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "software\sim_assets\create_correction_panel.py") `
    $cleanPng $distortedPng $rtlPng $goldenPng --output $panelPng
exit $LASTEXITCODE

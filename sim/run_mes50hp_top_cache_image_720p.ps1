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
$resultDirectory = Join-Path $projectRoot "result\sim_assets\cache_full_chain_1280x720"
$runDirectory = Join-Path $projectRoot "xsim.dir\mes50hp_top_cache_image_1280x720"
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
    & xvlog -sv -d CACHE_IMAGE_720P -d "CACHE_WAYS_$CacheWays" -d "EXPECT_CACHE_WAYS_$CacheWays" `
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
        (Join-Path $projectRoot "sim\pgl50h_tile_cache_bank_ip_model.sv") `
        (Join-Path $projectRoot "rtl\platform\common\memory\cached_pixel_fetch_engine.sv") `
        (Join-Path $projectRoot "rtl\platform\common\control\algorithm_reset_tree.sv") `
        (Join-Path $projectRoot "rtl\algorithm\distortion\distortion_image_pipeline.sv") `
        (Join-Path $projectRoot "rtl\board\pgl50h\clock_reset.sv") `
        (Join-Path $projectRoot "rtl\board\pgl50h\mes50hp_top.sv") `
        (Join-Path $projectRoot "sim\tb_mes50hp_top_cache_image.sv")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_mes50hp_top_cache_image -s mes50hp_top_cache_image_720p_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $xsimOutput = & xsim mes50hp_top_cache_image_720p_sim -runall 2>&1
    $xsimExitCode = $LASTEXITCODE
    $xsimOutput | Write-Output
    if ($xsimExitCode -ne 0) { exit $xsimExitCode }
    if (($xsimOutput | Out-String) -notmatch "TEST_PASS: mes50hp_top_cache_image") {
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

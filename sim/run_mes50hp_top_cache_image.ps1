<#
.SYNOPSIS
Runs the 256x192 image-level distortion correction through RGBX Tile Cache.

.DESCRIPTION
Generates the source/golden assets and writes the RTL image, frame comparison,
and simulator work files below result/sim_assets/cache_full_chain_256x192.
#>

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$resultDirectory = Join-Path $projectRoot "result\sim_assets\cache_full_chain_256x192"
$runDirectory = Join-Path $projectRoot "xsim.dir\mes50hp_top_cache_image_256x192"
$cleanPng = Join-Path $resultDirectory "clean_reference_256x192.png"
$distortedPng = Join-Path $resultDirectory "distorted_input_256x192.png"
$distortedMem = Join-Path $resultDirectory "distorted_input_rgb888_256x192.mem"
$goldenPrefix = Join-Path $resultDirectory "corrected_q18_256x192"
$goldenMem = Join-Path $resultDirectory "golden_corrected_q18_256x192.mem"
$goldenPng = Join-Path $resultDirectory "golden_corrected_q18_256x192.png"
$rtlMem = Join-Path $resultDirectory "rtl_corrected_q18_256x192.mem"
$rtlPng = Join-Path $resultDirectory "rtl_corrected_q18_256x192.png"
$panelPng = Join-Path $resultDirectory "cache_correction_comparison.png"

New-Item -ItemType Directory -Force $resultDirectory | Out-Null
New-Item -ItemType Directory -Force $runDirectory | Out-Null

& py (Join-Path $projectRoot "software\sim_assets\create_checkerboard.py") `
    --width 256 --height 192 --square-size 32 --color --output $cleanPng
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "software\sim_assets\generate_distorted_input.py") `
    $cleanPng --output $distortedPng `
    --fx 180.0 --fy 180.0 --cx 127.5 --cy 95.5 `
    --k1 -0.25 --k2 0.05 --p1 0.001 --p2 -0.001
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "software\sim_assets\image_to_mem.py") `
    $distortedPng --output $distortedMem
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "software\sim_assets\generate_distortion_vectors.py") `
    $distortedPng --output-prefix $goldenPrefix --optimized-q18 `
    --fx 180.0 --fy 180.0 --cx 127.5 --cy 95.5 `
    --k1 -0.25 --k2 0.05 --p1 0.001 --p2 -0.001
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Push-Location $runDirectory
try {
    & xvlog -sv `
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

    & xelab tb_mes50hp_top_cache_image -s mes50hp_top_cache_image_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $xsimOutput = & xsim mes50hp_top_cache_image_sim -runall 2>&1
    $xsimExitCode = $LASTEXITCODE
    $xsimOutput | Write-Output
    if ($xsimExitCode -ne 0) { exit $xsimExitCode }
    if (($xsimOutput | Out-String) -notmatch "TEST_PASS: mes50hp_top_cache_image") {
        throw "XSim completed without the expected cache image pass marker."
    }
}
finally {
    Pop-Location
}

& py (Join-Path $projectRoot "software\sim_assets\compare_mem_frames.py") `
    $goldenMem $rtlMem --width 256 --height 192
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "result\tool\mem_to_png.py") `
    $goldenMem --width 256 --height 192 --output $goldenPng
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "result\tool\mem_to_png.py") `
    $rtlMem --width 256 --height 192 --output $rtlPng
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "software\sim_assets\create_correction_panel.py") `
    $cleanPng $distortedPng $rtlPng $goldenPng --output $panelPng
exit $LASTEXITCODE

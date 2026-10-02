<#
.SYNOPSIS
Generates a synthetic camera-distorted frame and corrects it with the RTL chain.

.DESCRIPTION
Final assets are isolated under result/sim_assets/correction_full_chain_256x192.
All Vivado XSim temporary files stay under xsim.dir/distortion_correction_image.
#>

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$resultDirectory = Join-Path $projectRoot "result\sim_assets\correction_full_chain_256x192"
$runDirectory = Join-Path $projectRoot "xsim.dir\distortion_correction_image"
$cleanPng = Join-Path $resultDirectory "clean_reference_256x192.png"
$distortedPng = Join-Path $resultDirectory "distorted_input_256x192.png"
$distortedMem = Join-Path $resultDirectory "distorted_input_256x192.mem"
$goldenPrefix = Join-Path $resultDirectory "corrected_256x192"
$goldenMem = Join-Path $resultDirectory "golden_corrected_256x192.mem"
$goldenPng = Join-Path $resultDirectory "golden_corrected_256x192.png"
$rtlMem = Join-Path $resultDirectory "rtl_corrected_256x192.mem"
$rtlPng = Join-Path $resultDirectory "rtl_corrected_256x192.png"
$panelPng = Join-Path $resultDirectory "correction_comparison.png"

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
    $distortedPng --output-prefix $goldenPrefix `
    --fx 180.0 --fy 180.0 --cx 127.5 --cy 95.5 `
    --k1 -0.25 --k2 0.05 --p1 0.001 --p2 -0.001
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot "rtl\distortion\coordinate_gen.sv") `
        (Join-Path $projectRoot "rtl\distortion\normalize.sv") `
        (Join-Path $projectRoot "rtl\distortion\coordinate_split.sv") `
        (Join-Path $projectRoot "rtl\distortion\distortion_core.sv") `
        (Join-Path $projectRoot "rtl\interpolation\bilinear_interp.sv") `
        (Join-Path $projectRoot "rtl\memory\pixel_fetch_engine.sv") `
        (Join-Path $projectRoot "rtl\distortion\distortion_image_pipeline.sv") `
        (Join-Path $projectRoot "sim\models\ddr_behavior_model.sv") `
        (Join-Path $projectRoot "sim\tb_distortion_correction_image.sv")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_distortion_correction_image -s distortion_correction_image_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xsim distortion_correction_image_sim -runall
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
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

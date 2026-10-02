<#
.SYNOPSIS
Runs the 256x192 RTL distortion-coordinate and Pixel Fetch image pipeline.

.DESCRIPTION
Final assets are written under result/sim_assets/full_chain_256x192.  All
Vivado XSim temporary files stay under xsim.dir/distortion_image_pipeline.
#>

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$resultDirectory = Join-Path $projectRoot "result\sim_assets\full_chain_256x192"
$runDirectory = Join-Path $projectRoot "xsim.dir\distortion_image_pipeline"
$inputPng = Join-Path $resultDirectory "color_checkerboard_256x192.png"
$inputMem = Join-Path $resultDirectory "color_checkerboard_256x192.mem"
$distortionPrefix = Join-Path $resultDirectory "barrel_256x192"
$goldenMem = Join-Path $resultDirectory "golden_barrel_256x192.mem"
$goldenPng = Join-Path $resultDirectory "golden_barrel_256x192.png"
$rtlMem = Join-Path $resultDirectory "rtl_full_chain_256x192.mem"
$rtlPng = Join-Path $resultDirectory "rtl_full_chain_256x192.png"
$panelPng = Join-Path $resultDirectory "full_chain_comparison.png"

New-Item -ItemType Directory -Force $resultDirectory | Out-Null
New-Item -ItemType Directory -Force $runDirectory | Out-Null

& py (Join-Path $projectRoot "software\sim_assets\create_checkerboard.py") `
    --width 256 --height 192 --square-size 32 --color --output $inputPng
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "software\sim_assets\image_to_mem.py") `
    $inputPng --output $inputMem
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "software\sim_assets\generate_distortion_vectors.py") `
    $inputPng --output-prefix $distortionPrefix `
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
        (Join-Path $projectRoot "sim\tb_distortion_image_pipeline.sv")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_distortion_image_pipeline -s distortion_image_pipeline_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xsim distortion_image_pipeline_sim -runall
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

& py (Join-Path $projectRoot "software\sim_assets\create_comparison_panel.py") `
    $inputPng $goldenPng $rtlPng --output $panelPng
exit $LASTEXITCODE

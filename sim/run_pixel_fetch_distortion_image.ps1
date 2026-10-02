<#
.SYNOPSIS
Builds 256x192 color distortion assets, runs the Pixel Fetch image test, and
writes all XSim temporary files under xsim.dir/pixel_fetch_distortion_image.
#>

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$assetsDirectory = Join-Path $projectRoot "result\sim_assets"
$runDirectory = Join-Path $projectRoot "xsim.dir\pixel_fetch_distortion_image"
$checkerboardPng = Join-Path $assetsDirectory "color_checkerboard_256x192.png"
$checkerboardMem = Join-Path $assetsDirectory "color_checkerboard_256x192.mem"
$distortionPrefix = Join-Path $assetsDirectory "barrel_256x192"
$goldenMem = Join-Path $assetsDirectory "golden_barrel_256x192.mem"
$rtlMem = Join-Path $assetsDirectory "rtl_barrel_256x192.mem"

New-Item -ItemType Directory -Force $assetsDirectory | Out-Null
New-Item -ItemType Directory -Force $runDirectory | Out-Null

& py (Join-Path $projectRoot "software\sim_assets\create_checkerboard.py") `
    --width 256 --height 192 --square-size 32 --color --output $checkerboardPng
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "software\sim_assets\image_to_mem.py") `
    $checkerboardPng --output $checkerboardMem
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "software\sim_assets\generate_distortion_vectors.py") `
    $checkerboardPng --output-prefix $distortionPrefix `
    --fx 180.0 --fy 180.0 --cx 127.5 --cy 95.5 `
    --k1 -0.25 --k2 0.05 --p1 0.001 --p2 -0.001
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot "rtl\interpolation\bilinear_interp.sv") `
        (Join-Path $projectRoot "rtl\memory\pixel_fetch_engine.sv") `
        (Join-Path $projectRoot "sim\models\ddr_behavior_model.sv") `
        (Join-Path $projectRoot "sim\tb_pixel_fetch_distortion_image.sv")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_pixel_fetch_distortion_image -s pixel_fetch_distortion_image_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xsim pixel_fetch_distortion_image_sim -runall
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}

& py (Join-Path $projectRoot "software\sim_assets\compare_mem_frames.py") `
    $goldenMem $rtlMem --width 256 --height 192
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "result\tool\mem_to_png.py") `
    $goldenMem --width 256 --height 192 `
    --output (Join-Path $assetsDirectory "golden_barrel_256x192.png")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& py (Join-Path $projectRoot "result\tool\mem_to_png.py") `
    $rtlMem --width 256 --height 192 `
    --output (Join-Path $assetsDirectory "rtl_barrel_256x192.png")
exit $LASTEXITCODE

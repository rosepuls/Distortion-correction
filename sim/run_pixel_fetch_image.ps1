<#!
.SYNOPSIS
Runs the 64x48 Pixel Fetch image simulation in an isolated xsim work folder.
#>

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot "xsim.dir\pixel_fetch_image"

New-Item -ItemType Directory -Force $runDirectory | Out-Null
New-Item -ItemType Directory -Force (Join-Path $projectRoot "result\sim_assets") | Out-Null

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot "rtl\interpolation\bilinear_interp.sv") `
        (Join-Path $projectRoot "rtl\memory\pixel_fetch_engine.sv") `
        (Join-Path $projectRoot "sim\models\ddr_behavior_model.sv") `
        (Join-Path $projectRoot "sim\tb_pixel_fetch_image.sv")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_pixel_fetch_image -s pixel_fetch_image_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xsim pixel_fetch_image_sim -runall
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}

& py (Join-Path $projectRoot "software\sim_assets\compare_identity_mem.py") `
    (Join-Path $projectRoot "result\sim_assets\checkerboard_64x48.mem") `
    (Join-Path $projectRoot "result\sim_assets\rtl_identity_64x48.mem") `
    --width 64 --height 48
exit $LASTEXITCODE

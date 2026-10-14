param(
    [switch]$SkipGenerate,
    [switch]$CompileOnly
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$vivadoRoot = 'D:\Xilinx\Vivado\2020.2'
$resultDirectory = Join-Path $projectRoot "result\sim_assets\cache_video_30frames_1280x720"
$runDirectory = Join-Path $projectRoot "xsim.dir\mes50hp_top_cache_video_1280x720"

New-Item -ItemType Directory -Force $resultDirectory | Out-Null
New-Item -ItemType Directory -Force $runDirectory | Out-Null

if (-not $SkipGenerate) {
    & py (Join-Path $projectRoot "software\sim_assets\generate_video_regression_frames.py") `
        --frame-count 30 --width 1280 --height 720 --output-directory $resultDirectory
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Push-Location $runDirectory
try {
    & (Join-Path $vivadoRoot 'bin\xvlog.bat') -sv `
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
        (Join-Path $projectRoot "sim\tb_mes50hp_top_cache_video.sv")
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & (Join-Path $vivadoRoot 'bin\xelab.bat') tb_mes50hp_top_cache_video -s mes50hp_top_cache_video_720p_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if ($CompileOnly) { exit 0 }

    $xsimOutput = & (Join-Path $vivadoRoot 'bin\xsim.bat') mes50hp_top_cache_video_720p_sim -R 2>&1
    $xsimExitCode = $LASTEXITCODE
    $xsimOutput | Write-Output
    if ($xsimExitCode -ne 0) { exit $xsimExitCode }
    if (($xsimOutput | Out-String) -notmatch "TEST_PASS: mes50hp_top_cache_video") {
        throw "XSim completed without the expected 30-frame pixel regression pass marker."
    }
}
finally {
    Pop-Location
}

$comparisonDirectory = Join-Path $resultDirectory "comparison"
& py (Join-Path $projectRoot "software\sim_assets\create_video_comparison.py") `
    --asset-directory $resultDirectory `
    --output-directory $comparisonDirectory `
    --frame-count 30
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

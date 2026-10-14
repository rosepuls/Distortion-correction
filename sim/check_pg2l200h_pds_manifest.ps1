$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$pdsPath = Join-Path $projectRoot 'boards\pg2l200h\pds\pg2l200h_rtl_synth\pg2l200h_rtl_synth.pds'
$fdcPath = Join-Path $projectRoot 'boards\pg2l200h\constraints\pg2l200h_board_top.fdc'

if (-not (Test-Path -LiteralPath $pdsPath)) {
    throw "Missing PDS project: $pdsPath"
}

$pdsRoot = Split-Path -Parent $pdsPath
$pdsText = Get-Content -LiteralPath $pdsPath -Raw
if ($pdsText -notmatch '\(_flow\s+fab_demo\b') {
    throw 'PDS flow identifier is not the Fabric Compiler value fab_demo.'
}

$requiredReferences = @(
    'source/rtl/algorithm/distortion/distortion_image_pipeline.sv',
    'source/rtl/platform/common/memory/cached_pixel_fetch_engine.sv',
    'source/rtl/board/pg2l200h/pg2l200h_board_top.sv',
    'source/rtl/vendor/pg2l200h/hdmi/ms72xx_ctl.v',
    'source/rtl/vendor/pg2l200h/ddr/wr_rd_ctrl_top.v',
    'source/rtl/vendor/pg2l200h/ddr/wr_fram_buf/wr_fram_buf.idf',
    'source/rtl/vendor/pg2l200h/ddr/rd_fram_buf/rd_fram_buf.idf',
    'source/ip/pango/pg2l200h/ddr3/ddr3_test.idf',
    'source/ip/pango/pg2l200h/video_pll/pll.idf',
    'source/ip/pango/pg2l200h/cfg_pll/cfg_pll.idf',
    'source/constraints/pg2l200h_board_top.fdc'
)

foreach ($requiredReference in $requiredReferences) {
    if (-not $pdsText.Contains($requiredReference)) {
        throw "PDS is missing a required design, IP, or constraint reference: $requiredReference"
    }
    $windowsReference = $requiredReference.Replace('/', '\')
    if (-not (Test-Path -LiteralPath (Join-Path $pdsRoot $windowsReference))) {
        throw "PDS reference does not exist: $requiredReference"
    }
}

if (-not (Test-Path -LiteralPath $fdcPath)) {
    throw "Missing board FDC: $fdcPath"
}

Write-Host 'PASS: PG2L200H PDS manifest includes design sources, IP, and FDC.'

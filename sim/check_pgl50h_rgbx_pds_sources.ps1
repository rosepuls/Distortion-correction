Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$pdsPath = Join-Path $projectRoot 'boards\pgl50h\pds\pgl50h_rtl_synth\pgl50h_rtl_synth.pds'
$pdsText = Get-Content -LiteralPath $pdsPath -Raw
$implPath = Join-Path $projectRoot 'boards\pgl50h\pds\pgl50h_rtl_synth\impl.tcl'
$implText = Get-Content -LiteralPath $implPath -Raw

$required = @(
    '../../../../rtl/platform/common/memory/pixel_tile_cache.sv',
    '../../../../rtl/platform/common/memory/ddr_burst_reader.sv',
    '../../../../rtl/platform/common/memory/cached_pixel_fetch_engine.sv',
    '../../../../rtl/platform/common/memory/tile_cache_bank_ram.sv',
    '../../../../rtl/platform/common/control/algorithm_reset_tree.sv',
    '../../../../rtl/algorithm/distortion/distortion_image_pipeline.sv',
    '../../../../rtl/vendor/pgl50h/memory/pgl50h_tile_cache_bank_ip.v',
    '../../../../rtl/board/pgl50h/ddr3_rgbx_cache_adapter.sv',
    '../../../../rtl/board/pgl50h/video_mode_720p30.sv'
)

foreach ($path in $required) {
    if ($pdsText -notmatch [regex]::Escape($path)) {
        throw "PDS RGBX source is missing: $path"
    }
}

$implRequired = @(
    'rtl/platform/common/memory/tile_cache_bank_ram.sv',
    'rtl/vendor/pgl50h/memory/pgl50h_tile_cache_bank_ip.v'
)
foreach ($path in $implRequired) {
    if ($implText -notmatch [regex]::Escape($path)) {
        throw "PDS impl.tcl source is missing: $path"
    }
}

$legacy = @(
    '../../../../rtl/board/pgl50h/ddr3_pixel_read_adapter.sv',
    '../../../../rtl/vendor/pgl50h/video/sync_vg.v'
)

foreach ($path in $legacy) {
    if ($pdsText -match [regex]::Escape($path)) {
        throw "PDS still selects the retired RGB888 source: $path"
    }
}

if ($implText -match 'ddr3_pixel_read_adapter\.sv|rtl/vendor/pgl50h/video/sync_vg\.v') {
    throw 'PDS impl.tcl still selects a retired source.'
}

Write-Host 'PASS: PDS selects the RGBX cache board path.'

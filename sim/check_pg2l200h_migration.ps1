param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$requiredFiles = @(
    'rtl/board/pg2l200h/pg2l200h_board_top.sv',
    'rtl/vendor/pg2l200h/hdmi/iic_dri.v',
    'rtl/vendor/pg2l200h/hdmi/ms72xx_ctl.v',
    'rtl/vendor/pg2l200h/ddr/wr_rd_ctrl_top.v',
    'rtl/vendor/pg2l200h/memory/tile_cache_bank_ip.v',
    'ip/pango/pg2l200h/ddr3/ddr3_test.idf',
    'ip/pango/pg2l200h/video_pll/pll.idf',
    'ip/pango/pg2l200h/cfg_pll/cfg_pll.idf',
    'boards/pg2l200h/constraints/pg2l200h_board_top.fdc',
    'boards/pg2l200h/pds/pg2l200h_rtl_synth/impl.tcl',
    'boards/pg2l200h/pds/pg2l200h_rtl_synth/pg2l200h_rtl_synth.pds'
)

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $ProjectRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing PG2L200H migration asset: $relativePath"
    }
}

$top = Get-Content -LiteralPath (Join-Path $ProjectRoot 'rtl/board/pg2l200h/pg2l200h_board_top.sv') -Raw
foreach ($requiredToken in @('module pg2l200h_board_top', 'GTP_INBUFGDS', 'ddr3_test', 'clk_p', 'clk_n', 'hd_scl', 'hd_sda')) {
    if ($top -notmatch [regex]::Escape($requiredToken)) {
        throw "PG2L200H board top is missing required token: $requiredToken"
    }
}

$impl = Get-Content -LiteralPath (Join-Path $ProjectRoot 'boards/pg2l200h/pds/pg2l200h_rtl_synth/impl.tcl') -Raw
if ($impl -notmatch 'set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676') {
    throw 'PG2L200H implementation script does not select Logos2 / PG2L200H-6FBB676.'
}
if ($impl -match 'PGL50H|MES50HP|DDR3_50H|ipml_sdpram|ipsxb_') {
    throw 'PG2L200H implementation script still contains a PGL50H-only dependency.'
}

$pds = Get-Content -LiteralPath (Join-Path $ProjectRoot 'boards/pg2l200h/pds/pg2l200h_rtl_synth/pg2l200h_rtl_synth.pds') -Raw
foreach ($requiredToken in @('(_family Logos2)', '(_device PG2L200H)', 'pg2l200h_board_top',
                             'ddr3_test.idf', 'pg2l200h_board_top.fdc')) {
    if ($pds -notmatch [regex]::Escape($requiredToken)) {
        throw "PG2L200H PDS project is missing required token: $requiredToken"
    }
}
if ($pds -match 'PGL50H|MES50HP|DDR3_50H|ipml_sdpram|ipsxb_') {
    throw 'PG2L200H PDS project still contains a PGL50H-only dependency.'
}

$tileCache = Get-Content -LiteralPath (Join-Path $ProjectRoot 'rtl/platform/common/memory/tile_cache_bank_ram.sv') -Raw
if ($tileCache -notmatch '\btile_cache_bank_ip\b') {
    throw 'The common Tile Cache wrapper does not use the board-neutral tile_cache_bank_ip interface.'
}
if ($tileCache -match 'pgl50h_tile_cache_bank_ip') {
    throw 'The common Tile Cache wrapper still directly depends on PGL50H.'
}

Write-Host 'PASS: PG2L200H migration skeleton, active PDS target, and neutral Tile Cache interface are consistent.'

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$topPath = Join-Path $projectRoot 'rtl/board/pg2l200h/pg2l200h_board_top.sv'
$fdcPath = Join-Path $projectRoot 'boards/pg2l200h/constraints/pg2l200h_board_top.fdc'

foreach ($path in @($topPath, $fdcPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing PG2L200H board asset: $path" }
}

$topText = Get-Content -LiteralPath $topPath -Raw
$activeFdc = Get-Content -LiteralPath $fdcPath | Where-Object { $_ -notmatch '^\s*#' }
$fdcText = $activeFdc -join "`n"
foreach ($requiredToken in @('module pg2l200h_board_top', 'clk_p', 'clk_n', 'GTP_INBUFGDS', 'ddr3_test')) {
    if ($topText -notmatch [regex]::Escape($requiredToken)) {
        throw "PG2L200H top is missing required token: $requiredToken"
    }
}
foreach ($requiredClock in @(
    'create_clock -name {sys_clk} [get_ports {sys_clk}] -period {37.000}',
    'create_clock -name {ref_clk} [get_ports {clk_p}] -period {8.0}',
    'create_clock -name {pixclk_in}'
)) {
    if ($fdcText -notmatch [regex]::Escape($requiredClock)) {
        throw "Missing required PG2L200H clock constraint: $requiredClock"
    }
}
foreach ($port in @('sys_clk', 'clk_p', 'clk_n', 'rst_in', 'pixclk_in', 'pix_clk', 'hd_scl', 'hd_sda', 'mem_dq', 'mem_dqs')) {
    if ($fdcText -notmatch ("p:" + [regex]::Escape($port))) {
        throw "FDC does not constrain required PG2L200H port: $port"
    }
}
if ($fdcText -match 'PGL50H|MES50HP|DDR3_50H') {
    throw 'PG2L200H FDC contains a legacy-board dependency.'
}

if ($fdcText -match 'u_ddr3_test_h') {
    throw 'PG2L200H FDC still references the obsolete DDR wrapper instance u_ddr3_test_h.'
}
foreach ($requiredDdrPath in @(
    'ddr3_controller.u_ddrphy_top.rst_clk_gpll/clkout0',
    'ddr3_controller.u_ddrphy_top.ddrphy_gpll/clkout0',
    'ddr3_controller.u_ddrphy_top.u_ddrphy_cpd'
)) {
    if ($fdcText -notmatch [regex]::Escape($requiredDdrPath)) {
        throw "FDC does not constrain the current DDR3 instance hierarchy: $requiredDdrPath"
    }
}

Write-Host 'PASS: PG2L200H board top, Logos2 clocks, and official FDC baseline are consistent.'

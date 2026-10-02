$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$topPath = Join-Path $projectRoot "rtl/board/mes50hp/pgl50h_board_top.sv"
$fdcPath = Join-Path $projectRoot "constraints/mes50hp/pgl50h_board_top.fdc"

if (-not (Test-Path -LiteralPath $topPath)) {
    throw "Missing board top: $topPath"
}
if (-not (Test-Path -LiteralPath $fdcPath)) {
    throw "Missing board constraint: $fdcPath"
}

$topText = Get-Content -LiteralPath $topPath -Raw
$portPattern = '(?m)^\s*(?:input|output|inout)\s+(?:wire|reg)?\s*(?:signed\s*)?(?:\[[^\]]+\]\s*)?([A-Za-z_][A-Za-z0-9_]*)'
$topPorts = [regex]::Matches($topText, $portPattern) |
    ForEach-Object { $_.Groups[1].Value } |
    Sort-Object -Unique

$activeFdc = Get-Content -LiteralPath $fdcPath |
    Where-Object { $_ -notmatch '^\s*#' }
$fdcText = $activeFdc -join "`n"
$constrainedPorts = [regex]::Matches($fdcText, 'p:([A-Za-z_][A-Za-z0-9_]*)(?:\[[0-9]+\])?') |
    ForEach-Object { $_.Groups[1].Value } |
    Sort-Object -Unique

$missing = $topPorts | Where-Object { $_ -notin $constrainedPorts }
$extra = $constrainedPorts | Where-Object { $_ -notin $topPorts }
if ($missing) {
    throw "Unconstrained top-level ports: $($missing -join ', ')"
}
if ($extra) {
    throw "Constraint references unknown top-level ports: $($extra -join ', ')"
}

$requiredClockFragments = @(
    'create_clock -name {sys_clk}',
    'create_clock -name {pixclk_in}',
    'create_generated_clock -name {video_pixel_clk}',
    'create_generated_clock -name {cfg_clk}',
    'ddr3_controller.I_GTP_CLKDIV/CLKDIVOUT'
)
foreach ($fragment in $requiredClockFragments) {
    if (-not $fdcText.Contains($fragment)) {
        throw "Missing required clock constraint fragment: $fragment"
    }
}

$requiredStatusIo = @(
    'define_attribute {p:ddr_init_done} {PAP_IO_VCCIO} {3.3}',
    'define_attribute {p:ddr_init_done} {PAP_IO_STANDARD} {LVCMOS33}',
    'define_attribute {p:ddr_init_done} {PAP_IO_DRIVE} {8}',
    'define_attribute {p:heart_beat_led} {PAP_IO_VCCIO} {3.3}',
    'define_attribute {p:heart_beat_led} {PAP_IO_STANDARD} {LVCMOS33}',
    'define_attribute {p:heart_beat_led} {PAP_IO_DRIVE} {4}'
)
foreach ($fragment in $requiredStatusIo) {
    if (-not $fdcText.Contains($fragment)) {
        throw "Status IO is incompatible with the MES50HP 3.3 V bank: $fragment"
    }
}

$requiredIp = @(
    "ip/pango/mes50hp_video_pll/pll.idf",
    "ip/pango/DDR3_50H/DDR3_50H.idf",
    "rtl/vendor/mes50hp/ddr/wr_fram_buf/wr_fram_buf.idf",
    "rtl/vendor/mes50hp/ddr/rd_fram_buf/rd_fram_buf.idf"
)
foreach ($relativePath in $requiredIp) {
    $absolutePath = Join-Path $projectRoot $relativePath
    if (-not (Test-Path -LiteralPath $absolutePath)) {
        throw "Missing imported IP descriptor: $relativePath"
    }
}

Write-Host "PASS: pgl50h_board_top ports, board constraints, clocks, and IP descriptors are consistent."

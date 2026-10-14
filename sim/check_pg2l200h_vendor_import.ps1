$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'rtl/vendor/pg2l200h/hdmi/iic_dri.v',
    'rtl/vendor/pg2l200h/hdmi/ms7200_ctl.v',
    'rtl/vendor/pg2l200h/hdmi/ms7210_ctl.v',
    'rtl/vendor/pg2l200h/hdmi/ms72xx_ctl.v',
    'rtl/vendor/pg2l200h/ddr/wr_buf.v',
    'rtl/vendor/pg2l200h/ddr/wr_cmd_trans.v',
    'rtl/vendor/pg2l200h/ddr/wr_ctrl.v',
    'rtl/vendor/pg2l200h/ddr/rd_ctrl.v',
    'rtl/vendor/pg2l200h/ddr/wr_rd_ctrl_top.v',
    'rtl/vendor/pg2l200h/ddr/wr_fram_buf/wr_fram_buf.idf',
    'rtl/vendor/pg2l200h/ddr/rd_fram_buf/rd_fram_buf.idf',
    'rtl/vendor/pg2l200h/video/sync_vg.v',
    'ip/pango/pg2l200h/video_pll/pll.v',
    'ip/pango/pg2l200h/video_pll/pll.idf',
    'ip/pango/pg2l200h/cfg_pll/cfg_pll.v',
    'ip/pango/pg2l200h/cfg_pll/cfg_pll.idf',
    'ip/pango/pg2l200h/ddr3/ddr3_test.v',
    'ip/pango/pg2l200h/ddr3/ddr3_test.idf'
)

$missing = $required | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $projectRoot $_) -PathType Leaf)
}
if ($missing) {
    throw "Missing PG2L200H vendor source: $($missing -join ', ')"
}

$ddrText = Get-Content -LiteralPath (Join-Path $projectRoot 'ip/pango/pg2l200h/ddr3/ddr3_test.idf') -Raw
if ($ddrText -notmatch 'ips2l_') {
    throw 'PG2L200H DDR3 IP does not contain the expected Logos2 ips2l implementation.'
}
if ($ddrText -match 'ipsxb_') {
    throw 'PG2L200H DDR3 IP contains an incompatible legacy implementation.'
}

Write-Host 'PASS: PG2L200H Logos2 vendor source inventory is complete.'

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'rtl/vendor/mes50hp/hdmi/iic_dri.v',
    'rtl/vendor/mes50hp/hdmi/ms7200_ctl.v',
    'rtl/vendor/mes50hp/hdmi/ms7210_ctl.v',
    'rtl/vendor/mes50hp/hdmi/ms72xx_ctl.v',
    'rtl/vendor/mes50hp/ddr/wr_buf.v',
    'rtl/vendor/mes50hp/ddr/wr_cmd_trans.v',
    'rtl/vendor/mes50hp/ddr/wr_ctrl.v',
    'rtl/vendor/mes50hp/ddr/rd_ctrl.v',
    'rtl/vendor/mes50hp/ddr/wr_rd_ctrl_top.v',
    'rtl/vendor/mes50hp/ddr/wr_fram_buf/wr_fram_buf.idf',
    'rtl/vendor/mes50hp/ddr/rd_fram_buf/rd_fram_buf.idf',
    'rtl/vendor/mes50hp/video/sync_vg.v',
    'ip/pango/mes50hp_video_pll/pll.v',
    'ip/pango/mes50hp_video_pll/pll.idf',
    'ip/pango/DDR3_50H/DDR3_50H.v',
    'ip/pango/DDR3_50H/DDR3_50H.idf'
)

$missing = @(
    $required | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $projectRoot $_) -PathType Leaf)
    }
)

if ($missing.Count -ne 0) {
    $missing | ForEach-Object { Write-Error "Missing project-local vendor source: $_" }
    exit 1
}

Write-Host 'Project-local MES50HP vendor source inventory is complete.'

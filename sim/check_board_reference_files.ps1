$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'board_reference/mes50hp/06_hdmi_loop/src/hdmi_loop.v',
    'board_reference/mes50hp/06_hdmi_loop/src/hdmi_loop.fdc',
    'board_reference/mes50hp/07_ddr3_test/ipcore/ddr3_test/ddr3_test.v',
    'board_reference/mes50hp/10_HDMI_DDR3_OV5640_test/source/rtl/DDR3_50H/DDR3_50H.v',
    'board_reference/mes50hp/10_HDMI_DDR3_OV5640_test/hdmi_ddr_ov5640_top.fdc'
)

$missing = @(
    $required | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $projectRoot $_) -PathType Leaf)
    }
)

if ($missing.Count -ne 0) {
    $missing | ForEach-Object { Write-Error "Missing official reference: $_" }
    exit 1
}

Write-Host 'Official MES50HP board references are complete.'

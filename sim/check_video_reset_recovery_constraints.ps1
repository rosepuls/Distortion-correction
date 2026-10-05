$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$resetSource = Get-Content -Raw (Join-Path $projectRoot 'rtl\board\pgl50h\clock_reset.sv')
$topSource = Get-Content -Raw (Join-Path $projectRoot 'rtl\board\pgl50h\pgl50h_board_top.sv')
$constraintSource = Get-Content -Raw (Join-Path $projectRoot 'boards\pgl50h\constraints\pgl50h_board_top.fdc')
$timingReportPath = Join-Path $projectRoot 'boards\pgl50h\pds\pgl50h_rtl_synth\report_timing\pgl50h_board_top.rtr'

if ($resetSource -notmatch 'reset_release\s*/\*\s*synthesis\s+syn_preserve\s*=\s*1\s*\*/') {
    throw 'FAIL: reset_release is not protected with syn_preserve.'
}

if ($resetSource -notmatch 'module\s+mes50hp_reset_sync_sync_only') {
    throw 'FAIL: video reset sync-only module is missing.'
}

if ($resetSource -notmatch 'always\s+@\(posedge\s+clk\)') {
    throw 'FAIL: sync-only reset module must not use an asynchronous reset sensitivity.'
}

if ($topSource -notmatch 'mes50hp_reset_sync_sync_only\s+video_reset_sync') {
    throw 'FAIL: video_reset_sync is not using the sync-only reset module.'
}

if ($topSource -notmatch 'wire\s+ddr_reset_n\s*;') {
    throw 'FAIL: board top is missing the sys_clk-synchronized DDR reset net.'
}

if ($topSource -notmatch 'mes50hp_reset_sync_sync_only\s+ddr_reset_sync\s*\(\s*\.clk\s*\(\s*sys_clk\s*\)\s*,\s*\.reset_n\s*\(\s*rstn_out\s*\)\s*,\s*\.rst_n\s*\(\s*ddr_reset_n\s*\)\s*\)\s*;') {
    throw 'FAIL: DDR reset must use the sync-only sys_clk release synchronizer so cfg_clk cannot drive an RS pin.'
}

if ($topSource -notmatch '(?s)DDR3_50H\s+ddr3_controller\s*\(.*?\.resetn\s*\(\s*ddr_reset_n\s*\)') {
    throw 'FAIL: DDR3_50H.resetn is not driven exclusively by ddr_reset_n.'
}

$cdcFalsePathPattern = 'set_false_path\s+-from\s+\[get_clocks\s+\{cfg_clk\}\]\s+-to\s+\[get_clocks\s+\{video_pixel_clk\}\]'
if ($constraintSource -notmatch $cdcFalsePathPattern) {
    throw 'FAIL: cfg_clk to video_pixel_clk CDC false path is missing.'
}

if ([regex]::Matches($constraintSource, $cdcFalsePathPattern).Count -ne 1) {
    throw 'FAIL: expected exactly one cfg_clk to video_pixel_clk CDC false path.'
}

$ddrCdcFalsePathPattern = 'set_false_path\s+-from\s+\[get_clocks\s+\{cfg_clk\}\]\s+-to\s+\[get_clocks\s+\{sys_clk\}\]'
if ($constraintSource -notmatch $ddrCdcFalsePathPattern) {
    throw 'FAIL: cfg_clk to sys_clk DDR-reset CDC false path is missing.'
}

if ([regex]::Matches($constraintSource, $ddrCdcFalsePathPattern).Count -ne 1) {
    throw 'FAIL: expected exactly one cfg_clk to sys_clk DDR-reset CDC false path.'
}

if ($constraintSource -match 'set_false_path\s+-to\s+\[get_pins') {
    throw 'FAIL: unresolved internal pin-level false path must not be imported by PDS.'
}

if (Test-Path $timingReportPath) {
    $timingSource = Get-Content -Raw $timingReportPath
    $pathBlocks = [regex]::Split($timingSource, '(?=Startpoint\s+:)')
    foreach ($pathBlock in $pathBlocks) {
        if ($pathBlock -match 'Path Group\s+:\s+video_pixel_clk' -and
            $pathBlock -match 'Clock cfg_clk\s+\(rising edge\)') {
            if ($pathBlock -notmatch 'Endpoint\s+:\s+video_reset_sync/reset_release\[[01]\]/') {
                throw 'FAIL: cfg_clk to video_pixel_clk report contains a non-reset endpoint.'
            }
        }
        if ($pathBlock -match 'Path Group\s+:\s+sys_clk' -and
            $pathBlock -match 'Clock cfg_clk\s+\(rising edge\)') {
            if ($pathBlock -notmatch 'Endpoint\s+:\s+ddr_reset_sync/reset_release\[[01]\]/') {
                throw 'FAIL: cfg_clk to sys_clk report contains a non-DDR-reset endpoint.'
            }
        }
    }
}

Write-Output 'TEST_PASS: video_reset_recovery_constraints'

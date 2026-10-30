param(
    [string]$PdsShell = 'D:\Pango\PDS_2022.2-SP6.4\bin\pds_shell.exe',
    [switch]$FinalizeOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$project = Join-Path $projectRoot 'HDMI_IN_DDR3_HDMI_OUT.pds'
$log = Join-Path $projectRoot 'stage12-super-resolution-build.log'
$sourceFic = Join-Path $projectRoot 'synthesize\HDMI_IN_DDR3_HDMI_OUT_top_syn.fic'
$ficTemplate = Join-Path $projectRoot 'debug_core.fic'
$outputFic = Join-Path $projectRoot 'generate_bitstream\HDMI_IN_DDR3_HDMI_OUT_top.fic'
$bitstream = Join-Path $projectRoot 'generate_bitstream\HDMI_IN_DDR3_HDMI_OUT_top.sbit'
$timing = Join-Path $projectRoot 'report_timing\HDMI_IN_DDR3_HDMI_OUT_top.rtr'

if (-not $FinalizeOnly) {
    if (-not (Test-Path -LiteralPath $PdsShell -PathType Leaf)) {
        throw "PDS shell missing: $PdsShell"
    }
    if (-not (Test-Path -LiteralPath $ficTemplate -PathType Leaf)) {
        throw "Debug core template missing: $ficTemplate"
    }
    New-Item -ItemType Directory -Path (Split-Path $sourceFic -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $ficTemplate -Destination $sourceFic -Force
    Push-Location $projectRoot
    try {
        & $PdsShell -project $project -run gen_bit_stream *> $log
        if ($LASTEXITCODE -ne 0) { throw "PDS failed: $log" }
    } finally { Pop-Location }
}

foreach ($required in @($log, $sourceFic, $bitstream, $timing)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing build artifact: $required"
    }
}
if (Select-String -LiteralPath $log -Pattern '^E:' -Quiet) {
    throw "PDS reported an error: $log"
}
if (-not (Select-String -LiteralPath $log -Pattern '^Core Insertion Complete' -Quiet)) {
    throw "Fabric Debugger core insertion not confirmed: $log"
}
if (-not (Select-String -LiteralPath $log -Pattern 'Action from compile to gen_bit_stream:' -Quiet)) {
    throw "Bitstream flow completion not confirmed: $log"
}
if (-not (Select-String -LiteralPath $timing -Pattern 'Design Summary : All Constraints Met' -Quiet)) {
    throw "Timing constraints failed: $timing"
}
$ficLines = Get-Content -LiteralPath $sourceFic
$channels = @($ficLines | Where-Object {
    $_ -match '^Project\.unit<0>\.triggerChannel<0><\d+>='
})
if ($channels.Count -ne 256) {
    throw "Expected 256 Fabric Debugger channels, found $($channels.Count)"
}
foreach ($signal in @(
        'fram_buf/raw_input_vsync_count',
        'fram_buf/input_published_count',
        'fram_buf/copied_count',
        'fram_buf/display_take_count',
        'fram_buf/capture_dropped_count',
        'fram_buf/output_dropped_count',
        'fram_buf/capture_rejected_count',
        'fram_buf/capture_abort_count',
        'fram_buf/incomplete_output_count',
        'fram_buf/copy_error_count',
        'fram_buf/perf_frame_cycles',
        'fram_buf/perf_coord_stall_cycles')) {
    if (-not ($ficLines | Where-Object { $_ -like "*=$signal" })) {
        throw "Missing diagnostic FIC bus: $signal"
    }
}
Copy-Item -LiteralPath $sourceFic -Destination $outputFic -Force
(Get-Item -LiteralPath $outputFic).LastWriteTime = (Get-Item -LiteralPath $bitstream).LastWriteTime

Write-Host 'PASS: Stage 12 Stage 11 super-resolution bitstream generated and timing met.'
Write-Host "BITSTREAM: $bitstream"
Write-Host "BITSTREAM_SHA256: $((Get-FileHash -LiteralPath $bitstream -Algorithm SHA256).Hash)"
Write-Host "FIC: $outputFic"
Write-Host "FIC_SHA256: $((Get-FileHash -LiteralPath $outputFic -Algorithm SHA256).Hash)"

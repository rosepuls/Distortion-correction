param(
    [string]$PdsShell = 'D:\Pango\PDS_2022.2-SP6.4\bin\pds_shell.exe',
    [switch]$FinalizeOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$project = Join-Path $projectRoot 'HDMI_IN_DDR3_HDMI_OUT.pds'
$log = Join-Path $projectRoot 'stage9-bicubic-build.log'
$sourceFic = Join-Path $projectRoot 'synthesize\HDMI_IN_DDR3_HDMI_OUT_top_syn.fic'
$ficTemplate = Join-Path $projectRoot 'fabric_debugger\HDMI_IN_DDR3_HDMI_OUT_top_template.fic'
$ficConfigurator = Join-Path $projectRoot 'configure_angle_correction.py'
$outputFic = Join-Path $projectRoot 'generate_bitstream\HDMI_IN_DDR3_HDMI_OUT_top.fic'
$bitstream = Join-Path $projectRoot 'generate_bitstream\HDMI_IN_DDR3_HDMI_OUT_top.sbit'
$timing = Join-Path $projectRoot 'report_timing\HDMI_IN_DDR3_HDMI_OUT_top.rtr'

if (-not $FinalizeOnly) {
    if (-not (Test-Path -LiteralPath $PdsShell -PathType Leaf)) {
        throw "PDS shell missing: $PdsShell"
    }
    if (-not (Test-Path -LiteralPath $ficTemplate -PathType Leaf)) {
        throw "Fabric Debugger template missing: $ficTemplate"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $sourceFic) -Force | Out-Null
    Copy-Item -LiteralPath $ficTemplate -Destination $sourceFic -Force
    & python $ficConfigurator
    if ($LASTEXITCODE -ne 0) { throw 'Failed to configure the Stage 9 Fabric Debugger channel map.' }
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
$bilinearBuilt = Select-String -LiteralPath $log -Pattern 'Elaborating module pipelined_bilinear_interpolator' -Quiet
$bicubicBuilt = Select-String -LiteralPath $log -Pattern 'Elaborating module pipelined_catmull_rom_interpolator' -Quiet
if ($bilinearBuilt -eq $bicubicBuilt) {
    throw "Expected exactly one interpolation mode in this build: $log"
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
foreach ($signal in @('raw_input_vsync_count', 'input_published_count',
                     'copied_count', 'display_take_count', 'capture_dropped_count',
                     'perf_error_flags', 'perf_frame_cycles',
                     'perf_coord_stall_cycles', 'copy_gap_max_cycles',
                     'gap_input_at_max', 'gap_output_at_max',
                     'perf_diag_state')) {
    if (-not ($ficLines | Where-Object { $_ -like "*=fram_buf/$signal" })) {
        throw "Missing diagnostic FIC bus: $signal"
    }
}
if (-not ($ficLines | Where-Object {
    $_ -eq "Project.device.designInputFile=$($projectRoot.Replace('\', '/'))/synthesize/HDMI_IN_DDR3_HDMI_OUT_top_syn.adf"
})) {
    throw 'Fabric Debugger input does not point to this project synthesis output.'
}

Copy-Item -LiteralPath $sourceFic -Destination $outputFic -Force
if ((Get-FileHash -LiteralPath $sourceFic -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $outputFic -Algorithm SHA256).Hash) {
    throw 'Generated FIC does not match the synthesis FIC from this build.'
}

$mode = if ($bilinearBuilt) { 'bilinear' } else { 'Catmull-Rom bicubic' }
Write-Host "PASS: Stage 9 $mode bitstream generated and timing met."
Write-Host "BITSTREAM: $bitstream"
Write-Host "BITSTREAM_SHA256: $((Get-FileHash -LiteralPath $bitstream -Algorithm SHA256).Hash)"
Write-Host "FIC: $outputFic"
Write-Host "FIC_SHA256: $((Get-FileHash -LiteralPath $outputFic -Algorithm SHA256).Hash)"

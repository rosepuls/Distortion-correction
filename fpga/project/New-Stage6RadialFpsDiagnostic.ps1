param(
    [string]$SourceProject = (Join-Path $PSScriptRoot 'stage6_radial_ddr'),
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage6_radial_fps_debug')
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'New-Stage5FpsDiagnosticProject.ps1') `
    -SourceProject $SourceProject -ProjectDirectory $ProjectDirectory

# Connect per-frame timing counters from the transform engine to named top-level
# nets so the Fabric Core Inserter can capture them.
$frameFile = Join-Path $ProjectDirectory 'source\rtl\fram_buf.v'
$frameEncoding = [Text.Encoding]::GetEncoding(1252)
$frame = [IO.File]::ReadAllText($frameFile, $frameEncoding)
$copySequenceAnchor = '    wire [31:0] copy_completed_sequence;'
if (-not $frame.Contains($copySequenceAnchor)) { throw 'Perf counter declaration anchor missing.' }
$perfDeclarations = @'
    wire [31:0] copy_completed_sequence;
    wire [23:0] perf_frame_cycles /* synthesis PAP_MARK_DEBUG="true" */;
    wire [23:0] perf_coord_stall_cycles /* synthesis PAP_MARK_DEBUG="true" */;
    wire [23:0] perf_cache_miss_count /* synthesis PAP_MARK_DEBUG="true" */;
    wire [23:0] perf_cache_fill_cycles /* synthesis PAP_MARK_DEBUG="true" */;
    wire [23:0] perf_read_ar_wait_cycles /* synthesis PAP_MARK_DEBUG="true" */;
    wire [23:0] perf_read_response_wait_cycles /* synthesis PAP_MARK_DEBUG="true" */;
    wire [23:0] perf_write_wait_cycles /* synthesis PAP_MARK_DEBUG="true" */;
'@
$frame = $frame.Replace($copySequenceAnchor, $perfDeclarations.TrimEnd())
$copyErrorAnchor = '    wire [31:0] copy_error_count /* synthesis PAP_MARK_DEBUG="true" */;'
if (-not $frame.Contains($copyErrorAnchor)) { throw 'Perf error flag anchor missing.' }
$frame = $frame.Replace($copyErrorAnchor,
    $copyErrorAnchor + "`r`n" +
    '    wire [15:0] perf_error_flags /* synthesis PAP_MARK_DEBUG="true" */;')
$engineAnchor = '        .fetched_rows(), .tile_read_errors()'
if (-not $frame.Contains($engineAnchor)) { throw 'Perf engine port anchor missing.' }
$enginePorts = @'
        .fetched_rows(), .tile_read_errors(),
        .perf_frame_cycles(perf_frame_cycles),
        .perf_coord_stall_cycles(perf_coord_stall_cycles),
        .perf_cache_miss_count(perf_cache_miss_count),
        .perf_cache_fill_cycles(perf_cache_fill_cycles),
        .perf_read_ar_wait_cycles(perf_read_ar_wait_cycles),
        .perf_read_response_wait_cycles(perf_read_response_wait_cycles),
        .perf_write_wait_cycles(perf_write_wait_cycles)
'@
$frame = $frame.Replace($engineAnchor, $enginePorts.TrimEnd())
$statusAnchor = '    assign copy_physical_drained = !copy_source_busy &&'
if (-not $frame.Contains($statusAnchor)) { throw 'Perf error flag logic anchor missing.' }
$errorFlags = @'
    assign perf_error_flags = {
        7'd0,
        (output_dropped_count != 16'd0),
        copy_fatal_fault,
        display_frame_blocked,
        (incomplete_output_count != 16'd0),
        (copy_error_count != 32'd0),
        (write_protocol_error_count != 16'd0),
        (write_arbiter_error_count != 16'd0),
        (read_arbiter_error_count != 16'd0),
        (display_read_error_count != 16'd0)
    };
'@
$frame = $frame.Replace($statusAnchor, $errorFlags + "`r`n" + $statusAnchor)
[IO.File]::WriteAllText($frameFile, $frame, $frameEncoding)

# Reassign the 256 FIC channels to compact frame/drop counts, error flags, and
# seven per-frame timing/cache metrics. Each timing value fits in 24 bits at
# the measured 125 MHz DDR clock for a frame shorter than 134 ms.
$ficFile = Join-Path $ProjectDirectory 'synthesize\HDMI_IN_DDR3_HDMI_OUT_top_syn.fic'
$ficLines = [IO.File]::ReadAllLines($ficFile, [Text.Encoding]::UTF8)
$ficBase = @($ficLines | Where-Object {
    $_ -notmatch '^Project\.unit<0>\.(triggerChannel|triggerBus|busInserter)<' 
})
$fields = @(
    @{ Name = 'input_published_count'; Width = 16 },
    @{ Name = 'copied_count'; Width = 16 },
    @{ Name = 'display_take_count'; Width = 16 },
    @{ Name = 'capture_dropped_count'; Width = 16 },
    @{ Name = 'perf_error_flags'; Width = 16 },
    @{ Name = 'perf_frame_cycles'; Width = 24 },
    @{ Name = 'perf_coord_stall_cycles'; Width = 24 },
    @{ Name = 'perf_cache_miss_count'; Width = 24 },
    @{ Name = 'perf_cache_fill_cycles'; Width = 24 },
    @{ Name = 'perf_read_ar_wait_cycles'; Width = 24 },
    @{ Name = 'perf_read_response_wait_cycles'; Width = 24 },
    @{ Name = 'perf_write_wait_cycles'; Width = 24 },
    @{ Name = 'pipeline_status'; Width = 8; Lsb = 0 }
)
$ficMap = [Collections.Generic.List[string]]::new()
$channel = 0
$bus = 0
foreach ($field in $fields) {
    $lsb = if ($field.ContainsKey('Lsb')) { $field.Lsb } else { 0 }
    $msb = $lsb + $field.Width - 1
    $signal = "fram_buf/$($field.Name)"
    $indices = [Collections.Generic.List[string]]::new()
    for ($bit = 0; $bit -lt $field.Width; $bit++) {
        $indices.Add([string]($channel + $bit))
        $ficMap.Add("Project.unit<0>.triggerChannel<0><$($channel + $bit)>=$signal[$($lsb + $bit)]")
    }
    $ficMap.Add("Project.unit<0>.triggerBus<0><$channel><$($channel + $field.Width - 1)>=$signal")
    $ficMap.Add("Project.unit<0>.busInserter<$bus><$($indices -join '/')>=$signal")
    $channel += $field.Width
    $bus++
}
if ($channel -ne 256) { throw "Expected 256 FIC channels, generated $channel." }
$matchIndex = -1
for ($i = 0; $i -lt $ficBase.Count; $i++) {
    if ($ficBase[$i] -like 'Project.unit<0>.triggerMatchCount<0>=*') { $matchIndex = $i; break }
}
if ($matchIndex -lt 0) { throw 'FIC trigger-match anchor missing.' }
$newFic = @()
$newFic += $ficBase[0..($matchIndex - 1)]
$newFic += $ficMap.ToArray()
$newFic += $ficBase[$matchIndex..($ficBase.Count - 1)]
[IO.File]::WriteAllLines($ficFile, $newFic, [Text.UTF8Encoding]::new($false))

$readme = @'
# Stage 6 Brown-Conrady performance profile

This project clones stage6_radial_ddr with the same fixed visual trial:
k1=-0.25, k2=+0.0625, p1=+0.03125 and p2=-0.03125, using
x=(u-640)/512 and y=(v-360)/512. The Fabric DebugCore exposes frame counts,
drop counters, sticky error flags, and per-frame timing/cache counters.
Program this project's .sbit and import its matching .fic. See README_JTAG.md
for the channel map and measurement procedure.
'@
[IO.File]::WriteAllText((Join-Path $ProjectDirectory 'README.md'), $readme,
    (New-Object Text.UTF8Encoding($false)))

$jtagFile = Join-Path $ProjectDirectory 'README_JTAG.md'
$jtag = @'
# Stage 6 performance profile: JTAG channel map

Program `generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit` and import the
matching `.fic` from the same build. Use a moving 1280×720@60 HDMI pattern.
Capture two Listing snapshots about 60 seconds apart for cumulative frame and
drop counts. Per-frame timing/cache fields show the most recently completed
transform at each capture.

| Channels | Signal | Meaning |
|---|---|---|
| 0–15 | `input_published_count[15:0]` | Published input frames, low 16 bits |
| 16–31 | `copied_count[15:0]` | Completed transforms, low 16 bits |
| 32–47 | `display_take_count[15:0]` | New output frames selected for display |
| 48–63 | `capture_dropped_count[15:0]` | Dropped input frames |
| 64–79 | `perf_error_flags[15:0]` | Error and live status flags; see bit map below |
| 80–103 | `perf_frame_cycles[23:0]` | DDR cycles from transform start through write drain |
| 104–127 | `perf_coord_stall_cycles[23:0]` | Cycles coordinate input was backpressured |
| 128–151 | `perf_cache_miss_count[23:0]` | Tile refill starts during the frame |
| 152–175 | `perf_cache_fill_cycles[23:0]` | Cycles spent refilling/retrying cache misses |
| 176–199 | `perf_read_ar_wait_cycles[23:0]` | Read request cycles waiting for arbiter/DDR acceptance |
| 200–223 | `perf_read_response_wait_cycles[23:0]` | Cycles waiting for DDR read data during a tile row |
| 224–247 | `perf_write_wait_cycles[23:0]` | Output AW and W backpressure cycles combined |
| 248–255 | `pipeline_status[7:0]` | Live status flags from the existing frame pipeline |

`perf_error_flags` bit 0 is display-read error, bit 1 read-arbiter error,
bit 2 write-arbiter error, bit 3 write-protocol error, bit 4 transform error,
bit 5 incomplete output, bit 6 display blocked, bit 7 fatal transform fault,
and bit 8 indicates an output drop. Bits 9–15 are reserved. A 24-bit cycle counter represents up to 134 ms at
125 MHz; values are per-frame snapshots, not cumulative totals.

The fixed mapper coefficients are visual trial values, not camera calibration.
The profile measures stalls for this exact mapper and input scene.
'@
[IO.File]::WriteAllText($jtagFile, $jtag,
    (New-Object Text.UTF8Encoding($false)))

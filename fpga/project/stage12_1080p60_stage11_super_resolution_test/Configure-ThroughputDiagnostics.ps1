param([string]$ProjectRoot = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$path = Join-Path $root 'debug_core.fic'
$fic = Get-Content -LiteralPath $path

# Preserve the existing Cache lookup stall counters, split reservation-full
# stalls, and expose the writer-side ready backpressure for one frame.
$buses = @(
    @{ Signal='fram_buf/raw_input_vsync_count'; Width=12 },
    @{ Signal='fram_buf/input_published_count'; Width=12 },
    @{ Signal='fram_buf/copied_count'; Width=12 },
    @{ Signal='fram_buf/display_take_count'; Width=12 },
    @{ Signal='fram_buf/capture_dropped_count'; Width=12 },
    @{ Signal='fram_buf/output_dropped_count'; Width=12 },
    @{ Signal='fram_buf/perf_frame_cycles'; Width=22 },
    @{ Signal='fram_buf/perf_coord_stall_cycles'; Width=21 },
    @{ Signal='fram_buf/perf_cache_miss_count'; Width=16 },
    @{ Signal='fram_buf/perf_read_first_beat_wait_cycles'; Width=20 },
    @{ Signal='fram_buf/perf_cache_capacity_pipe_block_cycles'; Width=21 },
    @{ Signal='fram_buf/perf_cache_fill_block_cycles'; Width=21 },
    @{ Signal='fram_buf/perf_output_backpressure_fic'; Width=21 },
    @{ Signal='fram_buf/perf_cache_retry_miss_block_cycles'; Width=21 },
    @{ Signal='fram_buf/perf_cache_capacity_block_cycles'; Width=21 }
)

$busLines = [System.Collections.Generic.List[string]]::new()
$channelLines = [System.Collections.Generic.List[string]]::new()
$channel = 0
$busIndex = 0
foreach ($bus in $buses) {
    $start = $channel
    $end = $start + $bus.Width - 1
    $channels = @($start..$end)
    $busLines.Add("Project.unit<0>.triggerBus<0><$start><$end>=$($bus.Signal)")
    $busLines.Add("Project.unit<0>.busInserter<$busIndex><$($channels -join '/')>=$($bus.Signal)")
    foreach ($bit in 0..($bus.Width - 1)) {
        $channelLines.Add("Project.unit<0>.triggerChannel<0><$channel>=$($bus.Signal)[$bit]")
        $channel++
    }
    $busIndex++
}
if ($channel -ne 256) { throw "Expected 256 mapped channels, generated $channel" }

$header = @($fic | Where-Object {
    $_ -notmatch '^Project\.unit<0>\.(triggerBus<0>|busInserter<|triggerChannel<0><\d+>=)'
})
$adf = (Join-Path $root 'synthesize\HDMI_IN_DDR3_HDMI_OUT_top_syn.adf').Replace('\','/')
$header = @($header | ForEach-Object {
    if ($_ -match '^Project\.device\.designInputFile=') {
        "Project.device.designInputFile=$adf"
    } elseif ($_ -match '^Project\.unit<0>\.triggerPortWidth=') {
        'Project.unit<0>.triggerPortWidth=256'
    } else { $_ }
})
$firstChannel = [Array]::FindIndex([string[]]$header, [Predicate[string]]{ param($line) $line -match '^Project\.unit<0>\.triggerMatchCount<0>=' })
if ($firstChannel -ge 0) {
    $header = @($header[0..$firstChannel]) + @($busLines) + @($header[($firstChannel + 1)..($header.Count - 1)])
} else {
    $header = @($header) + @($busLines)
}
$output = @($header) + @('') + @($channelLines)
[IO.File]::WriteAllLines($path, $output, (New-Object Text.UTF8Encoding($false)))
Write-Host "PASS: generated 256 channel mappings and $($buses.Count) FIC buses in $path"

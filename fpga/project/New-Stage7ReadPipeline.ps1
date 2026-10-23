param(
    [string]$SourceProject = (Join-Path $PSScriptRoot 'stage8_read_wait_profile'),
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage7_read_pipeline_16x8')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $SourceProject -PathType Container)) {
    throw "Source project missing: $SourceProject"
}
if (Test-Path -LiteralPath $ProjectDirectory) {
    throw "Refusing to overwrite: $ProjectDirectory"
}
$source = (Resolve-Path -LiteralPath $SourceProject).Path
$destination = [IO.Path]::GetFullPath($ProjectDirectory)
$projectsRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
if ((Split-Path -Parent $destination) -ne $projectsRoot) {
    throw 'Destination must be a direct child of fpga/project.'
}

$ficName = 'HDMI_IN_DDR3_HDMI_OUT_top_syn.fic'
$ficSource = Join-Path $source (Join-Path 'synthesize' $ficName)
if (-not (Test-Path -LiteralPath $ficSource -PathType Leaf)) {
    throw "FIC template missing: $ficSource"
}

# Copy project inputs only; generated build outputs belong to each candidate.
$excludedDirs = @('compile','synthesize','device_map','place_route','report_timing',
    'generate_bitstream','generate_netlist','constraint_check','report_power',
    'log','logbackup','.dide')
$excludedFiles = @('*.log','*.csv','*.sbit','*.smsk','*.bgr','*.vcd','*.lock')
New-Item -ItemType Directory -Path $destination | Out-Null
$prefix = $source.TrimEnd('\') + '\'
Get-ChildItem -LiteralPath $source -File -Force -Recurse | Where-Object {
    $relative = $_.FullName.Substring($prefix.Length)
    $parts = $relative -split '[\\/]'
    $excluded = $false
    foreach ($pattern in $excludedFiles) {
        if ($_.Name -like $pattern) { $excluded = $true; break }
    }
    -not ($parts | Where-Object { $excludedDirs -contains $_ }) -and -not $excluded
} | ForEach-Object {
    $relative = $_.FullName.Substring($prefix.Length)
    $target = Join-Path $destination $relative
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -LiteralPath $_.FullName -Destination $target
}

$ficDir = Join-Path $destination 'synthesize'
New-Item -ItemType Directory -Path $ficDir -Force | Out-Null
$fic = [IO.File]::ReadAllText($ficSource, [Text.Encoding]::UTF8)
$oldDesign = ($fic -split "`n" | Where-Object {
    $_ -like 'Project.device.designInputFile=*'
} | Select-Object -First 1).TrimEnd("`r")
if (-not $oldDesign) { throw 'FIC design input path missing.' }
$newDesign = 'Project.device.designInputFile=' +
    (Join-Path $ficDir 'HDMI_IN_DDR3_HDMI_OUT_top_syn.adf').Replace('\','/')
$fic = $fic.Replace($oldDesign, $newDesign)
$labelMap = @{
    'fram_buf/perf_coord_stall_cycles' = 'fram_buf/perf_read_arbiter_wait_cycles'
    'fram_buf/perf_read_ar_wait_cycles' = 'fram_buf/perf_read_arready_wait_cycles'
    'fram_buf/perf_read_response_wait_cycles' = 'fram_buf/perf_read_first_beat_wait_cycles'
    'fram_buf/perf_write_wait_cycles' = 'fram_buf/perf_read_interbeat_wait_cycles'
}
foreach ($oldLabel in $labelMap.Keys) {
    $fic = $fic.Replace($oldLabel, $labelMap[$oldLabel])
}
[IO.File]::WriteAllText((Join-Path $ficDir $ficName), $fic,
    [Text.UTF8Encoding]::new($false))

$readme = @'
# Stage 7 read pipeline experiment (16x8 cache)

Independent throughput candidate based on the Stage 8 read-wait diagnostic
project. It retains the 16x8 cache and all four DDR read-wait counters. The
candidate permits up to four transform row bursts for one tile to be outstanding
and buffers the full 16-beat tile before cache writeback. Display reads retain
their own AXI ID and one-burst reservation path.

Build with `../Run-Stage7ReadPipeline.ps1`. Program this project's `.sbit` and
import the matching `.fic` from the same build. The FIC bus labels are corrected
for the Stage 8 diagnostic channel wiring.
'@
[IO.File]::WriteAllText((Join-Path $destination 'README.md'), $readme,
    [Text.UTF8Encoding]::new($false))
$jtagFile = Join-Path $destination 'README_JTAG.md'
$jtag = [IO.File]::ReadAllText($jtagFile, [Text.Encoding]::UTF8)
$jtag = $jtag.Replace('# Stage 8 DDR read wait profile: JTAG channel map',
    '# Stage 7 read pipeline: JTAG channel map')
[IO.File]::WriteAllText($jtagFile, $jtag, [Text.UTF8Encoding]::new($false))

Write-Host "PASS: created Stage 7 read pipeline project at $destination"

param(
    [string]$SourceProject = (Join-Path $PSScriptRoot 'stage8_read_wait_profile'),
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage7_read_pipeline_16x8'),
    [ValidateSet(16,32)][int]$CacheSets = 16,
    [ValidateSet(8)][int]$CacheWays = 8
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
    'log','logbackup','.dide','.work')
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

$topFile = Join-Path $destination 'source\rtl\fram_buf.v'
$sourceEncoding = [Text.Encoding]::GetEncoding(28591)
$topText = [IO.File]::ReadAllText($topFile, $sourceEncoding)
$cachePattern = '\.CACHE_SET_COUNT\(\d+\),\s*\.CACHE_WAYS\(\d+\)'
if ([regex]::Matches($topText, $cachePattern).Count -ne 1) {
    throw 'Expected one cache configuration in fram_buf.v.'
}
$topText = [regex]::Replace($topText, $cachePattern,
    ".CACHE_SET_COUNT($CacheSets), .CACHE_WAYS($CacheWays)")
[IO.File]::WriteAllText($topFile, $topText, $sourceEncoding)

$tileTestFile = Join-Path $destination 'sim\stage7_tile_fill_tb.sv'
if (Test-Path -LiteralPath $tileTestFile -PathType Leaf) {
    $tileTest = [IO.File]::ReadAllText($tileTestFile, [Text.Encoding]::UTF8)
    $tileTestPattern = 'cached_neighbor_reader\s*#\(\.SET_COUNT\(\d+\),\s*\.WAYS\(\d+\)\)'
    if ([regex]::Matches($tileTest, $tileTestPattern).Count -ne 1) {
        throw 'Expected one cache configuration in stage7_tile_fill_tb.sv.'
    }
    $tileTest = [regex]::Replace($tileTest, $tileTestPattern,
        "cached_neighbor_reader #(.SET_COUNT($CacheSets), .WAYS($CacheWays))")
    [IO.File]::WriteAllText($tileTestFile, $tileTest,
        [Text.UTF8Encoding]::new($false))
}

$readme = @'
# Stage 7 throughput experiment: <SETS>x<WAYS> cache

This candidate is copied from `<SOURCE>`. Its top-level cache has <SETS> sets
and <WAYS> ways. It retains the source project's DDR read pipeline and JTAG
counter wiring. Check the source project's README for its implementation details.

Run the simulations in `sim/`, then build with
`../Run-Stage7ReadPipeline.ps1 -ProjectDirectory <this directory>`.
Program only this project's generated `.sbit` and import its matching `.fic`.
This candidate has no hardware result until routing, timing and board checks pass.
'@
$readme = $readme.Replace('<SOURCE>', (Split-Path $source -Leaf)).
    Replace('<SETS>', [string]$CacheSets).Replace('<WAYS>', [string]$CacheWays)
[IO.File]::WriteAllText((Join-Path $destination 'README.md'), $readme,
    [Text.UTF8Encoding]::new($false))
$jtagFile = Join-Path $destination 'README_JTAG.md'
$jtag = [IO.File]::ReadAllText($jtagFile, [Text.Encoding]::UTF8)
$jtag = $jtag.Replace('# Stage 8 DDR read wait profile: JTAG channel map',
    '# Stage 7 read pipeline: JTAG channel map')
$intro = "After a successful build, program this project's generated ``.sbit`` " +
    "and import its matching ``.fic``. Capture two Listing snapshots about " +
    '60 seconds apart. Frame counters are cumulative; the 24-bit performance ' +
    'counters are snapshots from the most recently completed transform.'
$jtag = [regex]::Replace($jtag, '(?s)(\A#[^\r\n]+\r?\n\r?\n).*?(?=\r?\n\r?\n\| Channels)',
    { param($match) $match.Groups[1].Value + $intro })
[IO.File]::WriteAllText($jtagFile, $jtag, [Text.UTF8Encoding]::new($false))

Write-Host "PASS: created Stage 7 read pipeline project at $destination"

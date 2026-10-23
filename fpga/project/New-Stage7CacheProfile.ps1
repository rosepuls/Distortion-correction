param(
    [string]$SourceProject = (Join-Path $PSScriptRoot 'stage6_radial_fps_debug'),
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage7_cache_profile_32x8'),
    [int]$CacheSets = 32,
    [int]$CacheWays = 8
)

$ErrorActionPreference = 'Stop'
if ($CacheSets -notin @(16, 32) -or $CacheWays -notin @(4, 8)) {
    throw 'Use 16 or 32 sets and 4 or 8 ways.'
}
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

# Copy only project inputs. All compiled artifacts must come from this project's
# own PDS build; the source FIC is the sole exception because PDS consumes it.
$excludedDirs = @('compile','synthesize','device_map','place_route',
    'report_timing','generate_bitstream','generate_netlist',
    'constraint_check','report_power','log','logbackup','.dide')
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

$frameFile = Join-Path $destination 'source\rtl\fram_buf.v'
$encoding = [Text.Encoding]::GetEncoding(1252)
$frame = [IO.File]::ReadAllText($frameFile, $encoding)
$old = 'frame_identity_transform_engine #(.RADIAL_MAPPING(1), .RADIAL_DENOM_SHIFT(21)) copy_engine ('
$new = "frame_identity_transform_engine #(.RADIAL_MAPPING(1), .RADIAL_DENOM_SHIFT(21), .CACHE_SET_COUNT($CacheSets), .CACHE_WAYS($CacheWays)) copy_engine ("
if (-not $frame.Contains($old)) { throw 'Transform engine parameter anchor missing.' }
$frame = $frame.Replace($old, $new)
[IO.File]::WriteAllText($frameFile, $frame, $encoding)

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
[IO.File]::WriteAllText((Join-Path $ficDir $ficName), $fic,
    [Text.UTF8Encoding]::new($false))

$capacityKiB = $CacheSets * $CacheWays / 2
$readme = @"
# Stage 7 cache throughput profile

Independent copy of the Stage 6 Brown-Conrady performance diagnostic project.
The only datapath change is a $CacheSets-set, $CacheWays-way tile cache ($capacityKiB KiB of pixels)
instead of the 16-set, 4-way cache (32 KiB). The fixed mapping coefficients,
frame pipeline, and 256 Fabric DebugCore channels are unchanged.

Build with ../Run-Stage7CacheProfile.ps1 and the project directory argument.
Program this project's .sbit and import the .fic from the same build.
See README_JTAG.md for the channel map.
Compare approximately 60 seconds of the same moving 1280x720@60 input with the
recorded Stage 6 baseline.
"@
[IO.File]::WriteAllText((Join-Path $destination 'README.md'), $readme,
    [Text.UTF8Encoding]::new($false))
$jtagFile = Join-Path $destination 'README_JTAG.md'
$jtag = [IO.File]::ReadAllText($jtagFile, [Text.Encoding]::UTF8)
$jtag = $jtag.Replace('# Stage 6 performance profile: JTAG channel map',
    '# Stage 7 cache profile: JTAG channel map')
[IO.File]::WriteAllText($jtagFile, $jtag, [Text.UTF8Encoding]::new($false))

Write-Host "PASS: created Stage 7 cache profile at $destination"

param(
    [string]$SourceProject = (Join-Path $PSScriptRoot 'stage5_identity_ddr'),
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage12_720p_to_1080p30_bilinear_adaptive_sharpen_test')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $SourceProject -PathType Container)) {
    throw "Source project not found: $SourceProject"
}
if (Test-Path -LiteralPath $ProjectDirectory) {
    throw "Refusing to overwrite existing project: $ProjectDirectory"
}

$source = (Resolve-Path -LiteralPath $SourceProject).Path
$destination = [IO.Path]::GetFullPath($ProjectDirectory)
$projectsRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
if ((Split-Path -Parent $destination) -ne $projectsRoot) {
    throw 'Destination must be a direct child of fpga/project.'
}

$prefix = $source.TrimEnd('\') + '\'
$excludedDirs = @(
    'compile', 'synthesize', 'device_map', 'place_route', 'report_timing',
    'generate_bitstream', 'generate_netlist', 'constraint_check', 'report_power',
    'log', 'logbackup'
)
$excludedFiles = @(
    '*.log', '*.csv', '*.sbit', '*.smsk', '*.bgr', '*.vcd', '*.lock',
    'stderr.log', 'stdout.log'
)

New-Item -ItemType Directory -Path $destination | Out-Null
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

$readme = @'
# Stage 12 720p-to-1080p30 adaptive bilinear sharpening test

Independent feasibility project copied from Stage 5 identity DDR. It keeps
the 1280×720 capture path and the existing 2×2 tile-cache bilinear sampler,
then maps processed output samples to 1920×1080 and applies bounded adaptive
edge sharpening before DDR output. The HDMI output target is 1080p30.

This project intentionally has no Brown distortion correction, angle
correction, adaptive lighting LUT, or UART control. Those are later integration
steps after this project's image quality, 1080p30 throughput, and timing have
been measured. Stage 5 and later projects remain unchanged.

The copied PDS reports and bitstreams were excluded. Run new simulations and a
full PDS build from this project's own files before considering any bitstream
for the board. Simulation and timing closure do not replace board validation.
'@
[IO.File]::WriteAllText((Join-Path $destination 'README.md'), $readme, (New-Object Text.UTF8Encoding($false)))
New-Item -ItemType Directory -Path (Join-Path $destination 'sim') | Out-Null
Write-Host "PASS: copied clean Stage 5 identity project to $destination"

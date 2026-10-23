param(
    [string]$SourceProject = (Join-Path $PSScriptRoot 'stage3_dual_pool_copy_cdc_fix'),
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage5_identity_ddr')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $SourceProject -PathType Container)) { throw "Source project not found: $SourceProject" }
if (Test-Path -LiteralPath $ProjectDirectory) { throw "Refusing to overwrite existing project: $ProjectDirectory" }
$source = (Resolve-Path -LiteralPath $SourceProject).Path
$destination = [IO.Path]::GetFullPath($ProjectDirectory)
$projectsRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
if ((Split-Path -Parent $destination) -ne $projectsRoot) { throw 'Destination must be a direct child of fpga/project.' }
$prefix = $source.TrimEnd('\') + '\'
$excludedDirs = @('compile','synthesize','device_map','place_route','report_timing','generate_bitstream','generate_netlist','constraint_check','report_power','log','logbackup')
$excludedFiles = @('*.log','*.csv','*.sbit','*.smsk','*.bgr','*.vcd','*.lock','cdc-netlist-audit.txt')

New-Item -ItemType Directory -Path $destination | Out-Null
Get-ChildItem -LiteralPath $source -File -Force -Recurse | Where-Object {
    $relative = $_.FullName.Substring($prefix.Length)
    $parts = $relative -split '[\\/]'
    $excluded = $false
    foreach ($pattern in $excludedFiles) { if ($_.Name -like $pattern) { $excluded = $true; break } }
    -not ($parts | Where-Object { $excludedDirs -contains $_ }) -and -not $excluded
} | ForEach-Object {
    $relative = $_.FullName.Substring($prefix.Length)
    $target = Join-Path $destination $relative
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath $_.FullName -Destination $target
}

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$modules = @(
    'correction/identity_mapper.sv',
    'correction/coordinate_fifo.sv',
    'correction/identity_coordinate_pipeline.sv',
    'correction/bilinear_sample_planner.sv',
    'correction/pipelined_bilinear_interpolator.sv',
    'correction/stage5_identity_pipeline.sv',
    'memory/tile_cache_bank_ram.sv',
    'memory/pixel_tile_cache.sv',
    'memory/tile_row_ddr_adapter.sv',
    'memory/cached_neighbor_reader.sv',
    'memory/frame_identity_transform_engine.sv'
)
foreach ($module in $modules) {
    $relative = $module.Replace('/', '\')
    $target = Join-Path $destination (Join-Path 'source\rtl' $relative)
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath (Join-Path $repositoryRoot (Join-Path 'fpga\rtl' $relative)) -Destination $target
}

$frameBuffer = Join-Path $destination 'source\rtl\fram_buf.v'
$frameText = [IO.File]::ReadAllText($frameBuffer, [Text.Encoding]::GetEncoding(1252))
$old = 'frame_copy_engine copy_engine ('
if (-not $frameText.Contains($old)) { throw 'Frame-copy instance anchor was not found.' }
$frameText = $frameText.Replace($old, 'frame_identity_transform_engine copy_engine (')
$faultConnection = '.write_fault(write_arbiter_fault || write_protocol_fault)'
if (-not $frameText.Contains($faultConnection)) { throw 'Frame-copy fault connection was not found.' }
$frameText = $frameText.Replace($faultConnection,
    ".write_fault(write_arbiter_fault || write_protocol_fault),`r`n        .fetched_rows(), .tile_read_errors()")
$ledConnection = "(display_read_error_count != 16'd0)};"
if (-not $frameText.Contains($ledConnection)) { throw 'LED4 diagnostic anchor was not found.' }
$frameText = $frameText.Replace($ledConnection,
    "(display_read_error_count != 16'd0) || copy_fatal_fault};")
[IO.File]::WriteAllText($frameBuffer, $frameText, [Text.Encoding]::GetEncoding(1252))

$projectFile = Join-Path $destination 'HDMI_IN_DDR3_HDMI_OUT.pds'
$projectText = [IO.File]::ReadAllText($projectFile, [Text.Encoding]::UTF8)
$anchor = '                (_file "source/rtl/fram_buf.v"'
if (-not $projectText.Contains($anchor)) { throw 'PDS source-list anchor was not found.' }
$entries = ($modules | ForEach-Object {
    "                (_file `"source/rtl/$_`"`r`n                    (_format verilog)`r`n                    (_timespec `"2026-10-22T00:00:00`")`r`n                )`r`n"
}) -join ''
$projectText = $projectText.Replace($anchor, $entries + $anchor)
[IO.File]::WriteAllText($projectFile, $projectText, (New-Object Text.UTF8Encoding($false)))

$readme = @'
# Stage 5 DDR identity integration

Independent PG2L200H board project cloned from the Stage 3 CDC-fixed
camera -> DDR -> HDMI baseline. The frame ownership manager and capture/display
paths are unchanged. The middle frame-copy engine is replaced by a coordinate
pipeline, DDR tile-row reader, pixel tile cache, bilinear interpolator, and
DDR output writer. Identity coordinates should reproduce the source image.

LED4 reports display-adapter or transform fatal error, LED5 reports read-arbiter
error, LED6 reports an active display gate, and LED7 records any nonzero RGB
output. A transform fatal error requires reset and never publishes a partial
output frame. Keep the Stage 3 project as the board fallback.

This project must pass PDS timing before its bitstream is used on the board.
'@
[IO.File]::WriteAllText((Join-Path $destination 'README.md'), $readme, (New-Object Text.UTF8Encoding($false)))
Write-Host "PASS: created Stage 5 DDR identity project at $destination"

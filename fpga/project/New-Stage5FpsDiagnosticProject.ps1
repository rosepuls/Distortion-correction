param(
    [string]$SourceProject = (Join-Path $PSScriptRoot 'stage5_identity_ddr'),
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage5_identity_fps_debug')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $SourceProject -PathType Container)) { throw "Source project missing: $SourceProject" }
if (Test-Path -LiteralPath $ProjectDirectory) { throw "Refusing to overwrite: $ProjectDirectory" }
$source = (Resolve-Path -LiteralPath $SourceProject).Path
$destination = [IO.Path]::GetFullPath($ProjectDirectory)
$projectsRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
if ((Split-Path -Parent $destination) -ne $projectsRoot) { throw 'Destination must be a direct child of fpga/project.' }
$prefix = $source.TrimEnd('\') + '\'
$excludedDirs = @('compile','synthesize','device_map','place_route','report_timing','generate_bitstream','generate_netlist','constraint_check','report_power','log','logbackup')
$excludedFiles = @('*.log','*.csv','*.sbit','*.smsk','*.bgr','*.vcd','*.lock')
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

$frameFile = Join-Path $destination 'source\rtl\fram_buf.v'
$frame = [IO.File]::ReadAllText($frameFile, [Text.Encoding]::GetEncoding(1252))
$declarations = '    wire copy_active;'
if (-not $frame.Contains($declarations)) { throw 'Counter declaration anchor missing.' }
$frame = $frame.Replace($declarations, @'
    wire copy_active;
    reg [31:0] input_published_count /* synthesis PAP_MARK_DEBUG="true" */;
    reg [31:0] display_take_count /* synthesis PAP_MARK_DEBUG="true" */;
'@)
$frame = $frame.Replace('PAP_MARK_DEBUG="1"', 'PAP_MARK_DEBUG="true"')
$takeExpression = 'output_frame_start && display_take_ready &&' + "`r`n" +
                  '                      (!display_valid || output_frame_complete)'
if (-not $frame.Contains($takeExpression)) { throw 'Display-take expression anchor missing.' }
$frame = $frame.Replace($takeExpression, 'output_take_event')
$takeAnchor = '    frame_pipeline_ownership ownership ('
if (-not $frame.Contains($takeAnchor)) { throw 'Ownership anchor missing.' }
$frame = $frame.Replace($takeAnchor,
    "    wire output_take_event = output_frame_start && display_take_ready &&`r`n" +
    "        (!display_valid || output_frame_complete);`r`n" + $takeAnchor)
$resetAnchor = "            seen_output_vsync <= 1'b0;"
if (-not $frame.Contains($resetAnchor)) { throw 'Reset anchor missing.' }
$frame = $frame.Replace($resetAnchor,
    $resetAnchor + "`r`n            input_published_count <= 32'd0;" +
    "`r`n            display_take_count <= 32'd0;")
$incrementAnchor = '        end else begin' + "`r`n" +
                   '            if (output_frame_start)'
if (-not $frame.Contains($incrementAnchor)) { throw 'Counter increment anchor missing.' }
$frame = $frame.Replace($incrementAnchor,
    "        end else begin`r`n" +
    "            if (capture_publish && input_published_count != 32'hffff_ffff)`r`n" +
    "                input_published_count <= input_published_count + 1'b1;`r`n" +
    "            if (output_take_event && display_take_count != 32'hffff_ffff)`r`n" +
    "                display_take_count <= display_take_count + 1'b1;`r`n" +
    '            if (output_frame_start)')
[IO.File]::WriteAllText($frameFile, $frame, [Text.Encoding]::GetEncoding(1252))

$ficName = 'HDMI_IN_DDR3_HDMI_OUT_top_syn.fic'
$ficDirectory = Join-Path $destination 'synthesize'
New-Item -ItemType Directory -Path $ficDirectory | Out-Null
$ficSource = Join-Path $PSScriptRoot (Join-Path 'stage3_dual_pool_copy_debug\synthesize' $ficName)
if (-not (Test-Path -LiteralPath $ficSource -PathType Leaf)) { throw "FIC template missing: $ficSource" }
$fic = [IO.File]::ReadAllText($ficSource, [Text.Encoding]::UTF8)
$oldDesign = ($fic -split "`n" | Where-Object { $_ -like 'Project.device.designInputFile=*' } | Select-Object -First 1)
if (-not $oldDesign) { throw 'FIC design path missing.' }
$newDesign = 'Project.device.designInputFile=' + (Join-Path $destination 'synthesize\HDMI_IN_DDR3_HDMI_OUT_top_syn.adf').Replace('\','/')
$fic = $fic.Replace($oldDesign, $newDesign).Replace('stage3_dual_pool_copy_debug', 'stage5_identity_fps_debug')
[IO.File]::WriteAllText((Join-Path $ficDirectory $ficName), $fic, (New-Object Text.UTF8Encoding($false)))

$projectFile = Join-Path $destination 'HDMI_IN_DDR3_HDMI_OUT.pds'
$project = [IO.File]::ReadAllText($projectFile, [Text.Encoding]::UTF8)
$ficWidget = "        (_widget wgt_my_fic_src`r`n        )"
if (-not $project.Contains($ficWidget)) { throw 'Empty FIC widget anchor missing.' }
$replacement = @'
        (_widget wgt_my_fic_src
            (_input
                (_file "synthesize/HDMI_IN_DDR3_HDMI_OUT_top_syn.fic"
                    (_format text)
                    (_timespec "2026-10-22T00:00:00")
                )
            )
        )
'@
$project = $project.Replace($ficWidget, $replacement)
[IO.File]::WriteAllText($projectFile, $project, (New-Object Text.UTF8Encoding($false)))

$readme = @'
# Stage 5 FPS diagnostic project

Independent copy of stage5_identity_ddr. It adds saturating counters for
published input frames and output frames acquired by the display, then inserts
the same 256-channel Fabric DebugCore bus layout used by the earlier Stage 3
diagnostic project. The processor remains the DDR-backed identity algorithm.

Build this project separately. Program its own `.sbit` and import its matching
`.fic` in Pango Fabric Debugger. The Stage 3 `.sbit`/`.fic` pair cannot measure
the Stage 5 processor. See README_JTAG.md for channel mapping and procedure.
'@
[IO.File]::WriteAllText((Join-Path $destination 'README.md'), $readme, (New-Object Text.UTF8Encoding($false)))
$jtagSource = Join-Path $PSScriptRoot 'stage3_dual_pool_copy_debug\README_JTAG.md'
$jtag = [IO.File]::ReadAllText($jtagSource, [Text.Encoding]::UTF8)
$jtag = $jtag.Replace('Stage 3 DDR3 copy: JTAG frame-counter diagnostic',
    'Stage 5 DDR identity: JTAG frame-counter diagnostic')
$jtag = $jtag.Replace('stage3_dual_pool_copy_cdc_fix', 'stage5_identity_ddr')
$jtag = $jtag.Replace('Completed input-to-output frame copies',
    'Completed DDR-backed identity transforms')
$jtag = $jtag.Replace('Frame-copy errors', 'Frame-transform ownership errors')
$jtag = $jtag.Replace('This diagnostic bitstream is different from the current stable bitstream.',
    'Use only this project''s matching .sbit/.fic pair; the Stage 3 pair cannot measure Stage 5.')
$jtag += "`r`nFor Stage 5, record two Listing snapshots about 60 seconds apart. Divide each`r`n" +
    "counter delta by the actual elapsed seconds, then compare input published,`r`n" +
    "processed and display-take counts. Use a moving numbered 720p60 HDMI source;`r`n" +
    "the source page's browser FPS and the monitor's 60 Hz are separate measures.`r`n"
[IO.File]::WriteAllText((Join-Path $destination 'README_JTAG.md'), $jtag,
    (New-Object Text.UTF8Encoding($false)))
Write-Host "PASS: created Stage 5 FPS diagnostic project at $destination"

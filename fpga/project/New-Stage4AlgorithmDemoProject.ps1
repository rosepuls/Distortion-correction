param(
    [string]$SourceProject = (Join-Path $PSScriptRoot 'stage3_frame_pool_gate_fix'),
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage4_algorithm_demo')
)

$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $SourceProject -PathType Container)){throw "Source project not found: $SourceProject"}
if(Test-Path -LiteralPath $ProjectDirectory){throw "Refusing to overwrite existing project: $ProjectDirectory"}

$source=(Resolve-Path -LiteralPath $SourceProject).Path
$destination=[IO.Path]::GetFullPath($ProjectDirectory)
$projectsRoot=(Resolve-Path -LiteralPath $PSScriptRoot).Path
if((Split-Path -Parent $destination)-ne $projectsRoot){throw 'Destination must be a direct child of fpga/project.'}
$prefix=$source.TrimEnd('\')+'\'
$excludedDirs=@('compile','synthesize','device_map','place_route','report_timing','generate_bitstream','generate_netlist','constraint_check','report_power','log','logbackup')
$excludedFiles=@('*.log','*.csv','*.sbit','*.smsk','*.bgr','*.vcd')

New-Item -ItemType Directory -Path $destination|Out-Null
try{
    Get-ChildItem -LiteralPath $source -File -Force -Recurse | Where-Object {
        $relative=$_.FullName.Substring($prefix.Length)
        $parts=$relative -split '[\\/]'
        $file=$_; $excluded=$false
        foreach($pattern in $excludedFiles){if($file.Name -like $pattern){$excluded=$true;break}}
        -not($parts|Where-Object{$excludedDirs -contains $_}) -and -not $excluded
    } | ForEach-Object {
        $relative=$_.FullName.Substring($prefix.Length)
        $target=Join-Path $destination $relative
        $parent=Split-Path -Parent $target
        if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
        Copy-Item -LiteralPath $_.FullName -Destination $target
    }

    $repositoryRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $correctionSource=Join-Path $repositoryRoot 'fpga\rtl\correction'
    $correctionTarget=Join-Path $destination 'source\rtl\correction'
    New-Item -ItemType Directory -Path $correctionTarget -Force|Out-Null
    $modules=@(
        'demo_radial_mapper.sv','coordinate_fifo.sv','bilinear_sample_planner.sv',
        'procedural_pixel_reader.sv','bilinear_interpolator.sv',
        'stage4_demo_pipeline.sv','stage4_demo_frame_source.sv'
    )
    foreach($module in $modules){
        Copy-Item -LiteralPath (Join-Path $correctionSource $module) -Destination (Join-Path $correctionTarget $module)
    }
    Copy-Item -LiteralPath (Join-Path $correctionSource 'stage4_demo_fram_buf.v') `
        -Destination (Join-Path $destination 'source\rtl\fram_buf.v') -Force

    $projectFile=Join-Path $destination 'HDMI_IN_DDR3_HDMI_OUT.pds'
    $projectText=[IO.File]::ReadAllText($projectFile,[Text.Encoding]::UTF8)
    $anchor='                (_file "source/rtl/fram_buf.v"'
    if(-not $projectText.Contains($anchor)){throw 'PDS source-list anchor was not found.'}
    $entries=($modules|ForEach-Object{
@"
                (_file "source/rtl/correction/$_"
                    (_format verilog)
                    (_timespec "2026-10-21T14:00:00")
                )
"@
    }) -join ''
    $projectText=$projectText.Replace($anchor,$entries+$anchor)
    [IO.File]::WriteAllText($projectFile,$projectText,(New-Object Text.UTF8Encoding($false)))

    $readme=@'
# Stage 4 Algorithm Demo

This independent PG2L200H project keeps the accepted Stage 3 board clocks,
HDMI transmitter setup, DDR3 IP and pin constraints.  `fram_buf.v` is replaced
with the Stage 4 procedural algorithm path:

`radial Q16.16 mapper -> coordinate FIFO -> bilinear planner -> procedural
RGBX8888 grid reader -> bilinear interpolator -> HDMI output`.

The DDR3 device is initialized so the original board top and pins remain valid,
but the demo issues no AXI read or write requests.  It is an algorithm and video
timing test before the Tile Cache is connected to captured camera frames.

After a complete displayed frame, LED4/LED5/LED6 are expected on.  LED7 is the
pipeline error indicator and is expected off.  The displayed pattern is a
colored gradient with white 64-pixel grid lines, radially displaced outward;
the four corners fade to the constant-black border.
'@
    [IO.File]::WriteAllText((Join-Path $destination 'README.md'),$readme,(New-Object Text.UTF8Encoding($false)))
    Write-Host "PASS: created Stage 4 algorithm demo project at $destination"
}catch{
    if(Test-Path -LiteralPath $destination){
        $resolved=(Resolve-Path -LiteralPath $destination).Path
        if((Split-Path -Parent $resolved)-eq $projectsRoot){Remove-Item -LiteralPath $resolved -Recurse -Force}
    }
    throw
}

param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage6_radial_ddr'),
    [switch]$ResumeStage5Clone
)

$ErrorActionPreference = 'Stop'
$destination = [IO.Path]::GetFullPath($ProjectDirectory)
$projectsRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
if ((Split-Path -Parent $destination) -ne $projectsRoot) {
    throw 'Destination must be a direct child of fpga/project.'
}

if (Test-Path -LiteralPath $destination) {
    $stage5Readme = Join-Path $destination 'README.md'
    if (-not $ResumeStage5Clone -or
        -not (Test-Path -LiteralPath $stage5Readme -PathType Leaf) -or
        -not (Select-String -LiteralPath $stage5Readme -Pattern '^# Stage 5 DDR identity integration' -Quiet)) {
        throw 'Refusing to overwrite an existing project.'
    }
} else {
    & (Join-Path $PSScriptRoot 'New-Stage5IdentityProject.ps1') -ProjectDirectory $destination
}

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$mapperSource = Join-Path $repositoryRoot 'fpga\rtl\correction\stage6_brown_mapper.sv'
$mapperTarget = Join-Path $destination 'source\rtl\correction\demo_radial_mapper.sv'
Copy-Item -LiteralPath $mapperSource -Destination $mapperTarget

$frameBuffer = Join-Path $destination 'source\rtl\fram_buf.v'
$frameText = [IO.File]::ReadAllText($frameBuffer, [Text.Encoding]::GetEncoding(1252))
$oldInstance = 'frame_identity_transform_engine copy_engine ('
if (-not $frameText.Contains($oldInstance)) { throw 'Transform instance anchor not found.' }
$frameText = $frameText.Replace($oldInstance,
    'frame_identity_transform_engine #(.RADIAL_MAPPING(1), .RADIAL_DENOM_SHIFT(21)) copy_engine (')
[IO.File]::WriteAllText($frameBuffer, $frameText, [Text.Encoding]::GetEncoding(1252))

$projectFile = Join-Path $destination 'HDMI_IN_DDR3_HDMI_OUT.pds'
$projectText = [IO.File]::ReadAllText($projectFile, [Text.Encoding]::UTF8)
$anchor = '                (_file "source/rtl/correction/identity_mapper.sv"'
if (-not $projectText.Contains($anchor)) { throw 'PDS mapper source anchor not found.' }
$entry = "                (_file `"source/rtl/correction/demo_radial_mapper.sv`"`r`n                    (_format verilog)`r`n                    (_timespec `"2026-10-22T00:00:00`")`r`n                )`r`n"
$projectText = $projectText.Replace($anchor, $entry + $anchor)
[IO.File]::WriteAllText($projectFile, $projectText, (New-Object Text.UTF8Encoding($false)))

$readme = @'
# Stage 6 fixed Brown-Conrady visual trial on real DDR frames

Independent PG2L200H board project derived from the Stage 5 DDR identity
integration. The camera capture, frame pools, DDR tile cache, interpolator,
output writer, and HDMI display are preserved. The transform engine selects
the fixed Stage 6 Brown-Conrady mapper before the DDR-backed sampler.

With x=(u-640)/512, y=(v-360)/512 and r2=x*x+y*y, the output-to-source
map uses k1=-0.25, k2=+0.0625, p1=+0.03125 and p2=-0.03125.
These are visible trial values for a 120-degree wide-angle source, not
calibrated camera coefficients. The center pixel stays fixed by definition;
nearby pixels and the full frame are remapped. The fixed-point arithmetic
is in source/rtl/correction/demo_radial_mapper.sv (copied from
fpga/rtl/correction/stage6_brown_mapper.sv). Output frames are published
only after DDR writes drain, as in Stage 5.

Keep the Stage 5 identity bitstream as a direct board comparison. This
project needs PDS timing verification before programming.
'@
[IO.File]::WriteAllText((Join-Path $destination 'README.md'), $readme,
    (New-Object Text.UTF8Encoding($false)))
Write-Host "PASS: created Stage 6 fixed-radial DDR project at $destination"

param(
    [string]$SourceProject = (Join-Path $PSScriptRoot 'stage6_radial_ddr'),
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage6_radial_fps_debug')
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'New-Stage5FpsDiagnosticProject.ps1') `
    -SourceProject $SourceProject -ProjectDirectory $ProjectDirectory

$readme = @'
# Stage 6 Brown-Conrady FPS diagnostic

This project clones stage6_radial_ddr with the same fixed visual trial:
k1=-0.25, k2=+0.0625, p1=+0.03125 and p2=-0.03125, using
x=(u-640)/512 and y=(v-360)/512. The added Fabric DebugCore measures
input, processed and displayed frame counts. Program this project's .sbit
and import its matching .fic. See README_JTAG.md for the bus map.
'@
[IO.File]::WriteAllText((Join-Path $ProjectDirectory 'README.md'), $readme,
    (New-Object Text.UTF8Encoding($false)))

$jtagFile = Join-Path $ProjectDirectory 'README_JTAG.md'
$jtag = [IO.File]::ReadAllText($jtagFile, [Text.Encoding]::UTF8)
$jtag = $jtag.Replace('Stage 5 DDR identity: JTAG frame-counter diagnostic',
    'Stage 6 Brown-Conrady: JTAG frame-rate diagnostic')
$jtag = $jtag.Replace('stage5_identity_ddr', 'stage6_radial_ddr')
$jtag = $jtag.Replace('Completed DDR-backed identity transforms',
    'Completed Brown-Conrady transforms')
$jtag += "`r`nThe mapper uses k1=-0.25, k2=+0.0625, p1=+0.03125, p2=-0.03125`r`n" +
    "and normalized coordinates divided by 512. These are visual trial values.`r`n"
[IO.File]::WriteAllText($jtagFile, $jtag,
    (New-Object Text.UTF8Encoding($false)))

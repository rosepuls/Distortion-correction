param()

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$workspaceRoot = Split-Path -Parent $repoRoot
$vendorCandidates = @(
    Get-ChildItem -LiteralPath $workspaceRoot -Directory | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName '2_Demo\2_10_hdmi_loop\2_10_hdmi_loop\hdmi_loop.pds')
    }
)
if ($vendorCandidates.Count -ne 1) {
    throw "Expected one local vendor package beside the repository; found $($vendorCandidates.Count)."
}
$vendorRoot = $vendorCandidates[0].FullName
$loopDemo = Join-Path $vendorRoot '2_Demo\2_10_hdmi_loop\2_10_hdmi_loop'
$ddrDemo = Join-Path $vendorRoot '2_Demo\4_10_timing\4_10_HDMI_IN_DDR3_HDMI_OUT'
$projectDir = Join-Path $PSScriptRoot 'stage1_hdmi_loop'
$topSource = Join-Path $repoRoot 'fpga\rtl\video\hdmi_loop.v'
$clockConstraints = Join-Path $repoRoot 'fpga\constraints\hdmi_loop_720p60_clocks.fdc'
$pdsSource = Join-Path $loopDemo 'hdmi_loop.pds'
$fdcSource = Join-Path $loopDemo 'hdmi_loop.fdc'
$cfgIpSource = Join-Path $ddrDemo 'ipcore\cfg_pll'

if (Test-Path -LiteralPath $projectDir) {
    throw "Existing local project will not be overwritten: $projectDir"
}

$requiredFiles = @(
    $pdsSource,
    $fdcSource,
    $topSource,
    $clockConstraints,
    (Join-Path $cfgIpSource 'cfg_pll.idf'),
    (Join-Path $cfgIpSource 'cfg_pll.v')
)
$controlFiles = @('iic_dri.v', 'ms7200_ctl.v', 'ms7210_ctl.v', 'ms72xx_ctl.v')
foreach ($name in $controlFiles) {
    $requiredFiles += Join-Path (Join-Path $loopDemo 'source') $name
}
foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required source file is missing: $file"
    }
}

$pdsText = [System.IO.File]::ReadAllText($pdsSource)
$oldIdf = 'ipcore/PLL/PLL.idf'
$oldVerilog = 'ipcore/PLL/PLL.v'
if (-not $pdsText.Contains($oldIdf) -or -not $pdsText.Contains($oldVerilog) -or
    -not $pdsText.Contains('(_device PG2L200H)')) {
    throw 'Vendor PDS content differs from the expected PG2L200H loop example.'
}

$cfgIdfText = [System.IO.File]::ReadAllText((Join-Path $cfgIpSource 'cfg_pll.idf'))
if (-not $cfgIdfText.Contains('<device>PG2L200H</device>') -or
    -not $cfgIdfText.Contains('<package>FBB676</package>')) {
    throw 'The selected configuration PLL is not built for PG2L200H/FBB676.'
}

New-Item -ItemType Directory -Path (Join-Path $projectDir 'source') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $projectDir 'ipcore\cfg_pll') -Force | Out-Null

Copy-Item -LiteralPath $topSource -Destination (Join-Path $projectDir 'source\hdmi_loop.v')
foreach ($name in $controlFiles) {
    Copy-Item -LiteralPath (Join-Path (Join-Path $loopDemo 'source') $name) `
        -Destination (Join-Path $projectDir 'source')
}
& (Join-Path $PSScriptRoot 'Set-Stage1Edid.ps1') -ProjectDirectory $projectDir
foreach ($name in @('cfg_pll.idf', 'cfg_pll.v')) {
    Copy-Item -LiteralPath (Join-Path $cfgIpSource $name) `
        -Destination (Join-Path $projectDir 'ipcore\cfg_pll')
}

$pdsText = $pdsText.Replace($oldIdf, 'ipcore/cfg_pll/cfg_pll.idf')
$pdsText = $pdsText.Replace($oldVerilog, 'ipcore/cfg_pll/cfg_pll.v')
[System.IO.File]::WriteAllText(
    (Join-Path $projectDir 'hdmi_loop.pds'),
    $pdsText,
    (New-Object System.Text.UTF8Encoding($false))
)

$fdcText = [System.IO.File]::ReadAllText($fdcSource)
$fdcText += [Environment]::NewLine + [System.IO.File]::ReadAllText($clockConstraints)
[System.IO.File]::WriteAllText(
    (Join-Path $projectDir 'hdmi_loop.fdc'),
    $fdcText,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Created PDS project: $(Join-Path $projectDir 'hdmi_loop.pds')"
Write-Host 'Set the computer HDMI output to 1280x720 at 60 Hz before board validation.'

param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage2_ddr3_720p60')
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$workspaceRoot = Split-Path -Parent $repoRoot
$vendorCandidates = @(Get-ChildItem -LiteralPath $workspaceRoot -Directory | Where-Object {
    Test-Path -LiteralPath (Join-Path $_.FullName '2_Demo\4_10_timing\4_10_HDMI_IN_DDR3_HDMI_OUT\HDMI_IN_DDR3_HDMI_OUT.pds')
})
if ($vendorCandidates.Count -ne 1) {
    throw "Expected one PG2L200H vendor package beside the repository; found $($vendorCandidates.Count)."
}
$vendorDemo = Join-Path $vendorCandidates[0].FullName '2_Demo\4_10_timing\4_10_HDMI_IN_DDR3_HDMI_OUT'
$projectDir = [System.IO.Path]::GetFullPath($ProjectDirectory)
if ((Split-Path -Parent $projectDir) -ne [System.IO.Path]::GetFullPath($PSScriptRoot)) {
    throw 'The local PDS project must be a direct child of fpga/project.'
}
if (Test-Path -LiteralPath $projectDir) {
    throw "Existing local project will not be overwritten: $projectDir"
}

function Set-OneReplacement {
    param([string]$File, [string]$Pattern, [string]$Replacement)
    # Vendor Verilog mixes encodings in comments. All edited tokens are ASCII.
    $encoding = [System.Text.Encoding]::GetEncoding('iso-8859-1')
    $source = $encoding.GetString([System.IO.File]::ReadAllBytes($File))
    $matches = [regex]::Matches($source, $Pattern)
    if ($matches.Count -ne 1) {
        throw "Expected one match, found $($matches.Count): $Pattern in $File"
    }
    $result = [regex]::Replace($source, $Pattern, $Replacement)
    [System.IO.File]::WriteAllBytes($File, $encoding.GetBytes($result))
}

$pdsSource = Join-Path $vendorDemo 'HDMI_IN_DDR3_HDMI_OUT.pds'
$pdsText = [System.IO.File]::ReadAllText($pdsSource)
if (-not $pdsText.Contains('(_device PG2L200H)') -or
    -not $pdsText.Contains('source/rtl/HDMI_IN_DDR3_HDMI_OUT_top.v')) {
    throw 'The vendor PDS project is not the expected PG2L200H DDR3 example.'
}
foreach ($name in @('source', 'ipcore', 'HDMI_IN_DDR3_HDMI_OUT_top.fdc')) {
    if (-not (Test-Path -LiteralPath (Join-Path $vendorDemo $name))) {
        throw "Required vendor item is missing: $name"
    }
}

# Keep all proprietary RTL and generated DDR3 IP only in the ignored local PDS project.
New-Item -ItemType Directory -Path $projectDir | Out-Null
Copy-Item -LiteralPath (Join-Path $vendorDemo 'source') -Destination $projectDir -Recurse
Copy-Item -LiteralPath (Join-Path $vendorDemo 'ipcore') -Destination $projectDir -Recurse
Copy-Item -LiteralPath $pdsSource -Destination $projectDir
Copy-Item -LiteralPath (Join-Path $vendorDemo 'HDMI_IN_DDR3_HDMI_OUT_top.fdc') -Destination $projectDir

$top = Join-Path $projectDir 'source\rtl\HDMI_IN_DDR3_HDMI_OUT_top.v'
$frame = Join-Path $projectDir 'source\rtl\fram_buf.v'
$pllVerilog = Join-Path $projectDir 'ipcore\pll\pll.v'
$pllIdf = Join-Path $projectDir 'ipcore\pll\pll.idf'
$fdc = Join-Path $projectDir 'HDMI_IN_DDR3_HDMI_OUT_top.fdc'

& (Join-Path $PSScriptRoot 'Set-Stage1Edid.ps1') -ReceiverSource (Join-Path $projectDir 'source\hdmi\ms7200_ctl.v')

# 27 MHz * (19.25 * 2) / 14 = 74.25 MHz. Keep the IP metadata and generated RTL aligned.
Set-OneReplacement $pllVerilog '(localparam real\s+STATIC_RATIO0\s*=\s*)7\.0' '${1}14.0'
Set-OneReplacement $pllVerilog '(localparam integer\s+STATIC_DUTY0\s*=\s*)7\s*;' '${1}14;'
Set-OneReplacement $pllIdf '(<name>STATIC_RATIO0</name>\s*<value>)7\.0' '${1}14.0'
Set-OneReplacement $pllIdf '(<name>STATIC_DUTY0</name>\s*<value>)7' '${1}14'
Set-OneReplacement $pllIdf '(<name>CLKOUT0_REQ_FREQ_basicPage</name>\s*<value>)148\.50000000' '${1}74.25000000'

# CEA-861 720p60: 1280x720 active, 1650x750 total, positive 40/5 sync.
$timings = @{
    'V_TOTAL' = @('1125', '750'); 'V_FP' = @('4', '5');
    'V_BP' = @('36', '20'); 'V_SYNC' = @('5', '5');
    'V_ACT' = @('1080', '720'); 'H_TOTAL' = @('2200', '1650');
    'H_FP' = @('88', '110'); 'H_BP' = @('148', '220');
    'H_SYNC' = @('44', '40'); 'H_ACT' = @('1920', '1280')
}
foreach ($name in $timings.Keys) {
    $old = $timings[$name][0]
    $new = $timings[$name][1]
    if ($old -ne $new) {
        Set-OneReplacement $top "(parameter\s+$name\s*=\s*12'd)$old\s*;" ('${1}' + $new + ';')
    }
}
Set-OneReplacement $top '//MODE_1080p' '//MODE_720p60'
Set-OneReplacement $top '(\.clkout0\s*\(\s*pix_clk\s*\),\s*//)148\.5' '${1}74.25'
Set-OneReplacement $frame "(?m)^(\s*parameter\s+H_NUM\s*=\s*12'd)1920" '${1}1280'
Set-OneReplacement $frame "(?m)^(\s*parameter\s+V_NUM\s*=\s*12'd)1080" '${1}720'
Set-OneReplacement $fdc '(create_clock -name \{sys_clk\} \[get_ports \{sys_clk\}\] -period \{)37\.000(\} -waveform \{0\.000 )18\.500(\})' '${1}37.037${2}18.519${3}'
Set-OneReplacement $fdc '(create_clock -name \{pixclk_in\} \[get_ports \{pixclk_in\}\] -period \{)6\.734(\} -waveform \{0\.000 )3\.367(\})' '${1}13.468${2}6.734${3}'

# The vendor buffer uses 32-bit DDR words. A 720p RGB565 frame occupies
# 1280*720/2 = 460800 words; fram_buf overrides LINE_ADDR_WIDTH to 22,
# so the bank stride is 2^22 words and cannot overlap.
Write-Host "Created PDS project: $(Join-Path $projectDir 'HDMI_IN_DDR3_HDMI_OUT.pds')"
Write-Host 'Stage 2 baseline is RGB565; board validation and RGBX8888 conversion remain separate steps.'

param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage2_ddr3_720p60_shared_clock')
)

$ErrorActionPreference = 'Stop'
$projectDir = [System.IO.Path]::GetFullPath($ProjectDirectory)
if (Test-Path -LiteralPath $projectDir) {
    throw "Existing local project will not be overwritten: $projectDir"
}

& (Join-Path $PSScriptRoot 'New-Stage2Project.ps1') -ProjectDirectory $projectDir

function Replace-Once {
    param([string]$File, [string]$Old, [string]$New)
    # Preserve the mixed encoding in vendor RTL: every changed token is ASCII.
    $encoding = [System.Text.Encoding]::GetEncoding('iso-8859-1')
    $content = $encoding.GetString([System.IO.File]::ReadAllBytes($File))
    $matches = ([regex]::Matches($content, [regex]::Escape($Old))).Count
    if ($matches -ne 1) {
        throw "Expected exactly one match, found $matches in $File`: $Old"
    }
    [System.IO.File]::WriteAllBytes($File, $encoding.GetBytes($content.Replace($Old, $New)))
}

$top = Join-Path $projectDir 'source\rtl\HDMI_IN_DDR3_HDMI_OUT_top.v'
$fdc = Join-Path $projectDir 'HDMI_IN_DDR3_HDMI_OUT_top.fdc'

# Keep the original PLL and its lock-driven HDMI reset; only the output pixel
# clock source changes. This is a single-variable board experiment, not a fix.
Replace-Once $top '.clkout0  (  pix_clk    ),//74.25' '.clkout0  (  pix_clk_pll_unused    ),//74.25'
Replace-Once $top '//assign pix_clk = pixclk_in;' 'assign pix_clk = pixclk_in;'
Replace-Once $top '//PLL' "//PLL`r`nwire pix_clk_pll_unused;"

# pix_clk is now the input clock itself, so its old generated-clock group is stale.
Replace-Once $fdc 'set_clock_groups -name pix_clk -asynchronous -group [get_clocks {pix_clk}]' '# pix_clk is driven by the constrained pixclk_in port.'

Write-Host "Created shared-clock comparison project: $(Join-Path $projectDir 'HDMI_IN_DDR3_HDMI_OUT.pds')"

param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage2_ddr3_720p60_last_line')
)

$ErrorActionPreference = 'Stop'
$projectDir = [System.IO.Path]::GetFullPath($ProjectDirectory)
if (Test-Path -LiteralPath $projectDir) {
    throw "Existing local project will not be overwritten: $projectDir"
}

& (Join-Path $PSScriptRoot 'New-Stage2Project.ps1') -ProjectDirectory $projectDir

# Vendor RTL comments use mixed encodings. Change only ASCII tokens and
# preserve all other source bytes in this local, ignored PDS project.
$reader = Join-Path $projectDir 'source\rtl\rd_buf.v'
$encoding = [System.Text.Encoding]::GetEncoding('iso-8859-1')
$source = $encoding.GetString([System.IO.File]::ReadAllBytes($reader))
$old = 'wr_line != V_NUM'
$new = 'wr_line <= V_NUM'
$matches = ([regex]::Matches($source, [regex]::Escape($old))).Count
if ($matches -ne 1) {
    throw "Expected exactly one read-line guard, found $matches in $reader"
}

# The VS edge prefetches line 1 with wr_line=1, then increments it to 2.
# Active lines 1..719 must prefetch lines 2..720; active line 720 must stop.
# The vendor guard stops at wr_line=720 and omits the last prefetch.
[System.IO.File]::WriteAllBytes($reader, $encoding.GetBytes($source.Replace($old, $new)))

Write-Host "Created last-line comparison project: $(Join-Path $projectDir 'HDMI_IN_DDR3_HDMI_OUT.pds')"

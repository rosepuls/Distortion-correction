Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $projectRoot 'boards\pgl50h\pds\pgl50h_rtl_synth\pds.log'
if (!(Test-Path -LiteralPath $logPath)) {
    throw "PDS log not found: $logPath"
}

$log = Get-Content -LiteralPath $logPath -Raw
$summaryStart = $log.LastIndexOf('Mapping Summary:')
if ($summaryStart -lt 0) {
    throw 'PDS log has no Mapping Summary section.'
}
$summary = $log.Substring($summaryStart)

function Get-ResourceValue([string]$pattern, [string]$name, [string]$text = $summary) {
    $match = [regex]::Match($text, $pattern)
    if (!$match.Success) { throw "PDS resource is missing from final Mapping Summary: $name" }
    return [double]($match.Groups[1].Value -replace ',', '')
}

$lut = Get-ResourceValue 'Total LUTs:\s*([\d,]+(?:\.\d+)?)\s+of' 'Total LUTs'
$lutRam = Get-ResourceValue 'LUTs as dram:\s*([\d,]+(?:\.\d+)?)\s+of' 'LUTRAM'
$drm18k = Get-ResourceValue 'Total DRM18K\s*=\s*([\d,]+(?:\.\d+)?)\s+of' 'DRM18K'
$gtpRam32 = Get-ResourceValue 'GTP_RAM32X1DP\s+([\d,]+)\s+uses' 'GTP_RAM32X1DP' $log

Write-Host ("PGL50H resources: LUT={0} LUTRAM={1} DRM18K={2} GTP_RAM32X1DP={3}" -f $lut,$lutRam,$drm18k,$gtpRam32)
if ($lut -gt 42800 -or $lutRam -gt 17000 -or $drm18k -gt 134) {
    throw "PGL50H resource overflow: LUT=$lut LUTRAM=$lutRam DRM18K=$drm18k"
}
if ($gtpRam32 -gt 17000) {
    throw "PGL50H distributed RAM overflow: GTP_RAM32X1DP=$gtpRam32"
}
Write-Host 'PASS: PGL50H resource hard limits are satisfied.'

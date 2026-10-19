param(
    [string]$ProjectDirectory,
    [string]$ReceiverSource
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectDirectory) {
    $ProjectDirectory = Join-Path $PSScriptRoot 'stage1_hdmi_loop'
}

$edidFile = Join-Path $PSScriptRoot '..\edid\720p60.hex'
if (-not $ReceiverSource) {
    $ReceiverSource = Join-Path $ProjectDirectory 'source\ms7200_ctl.v'
}
$receiverSource = $ReceiverSource
if (-not (Test-Path -LiteralPath $receiverSource -PathType Leaf)) {
    throw "MS7200 source is missing: $receiverSource"
}

$hexText = [System.IO.File]::ReadAllText($edidFile)
$hexText = [regex]::Replace($hexText, '(?m)#.*$', '')
$tokens = @($hexText -split '\s+' | Where-Object { $_ -ne '' })
if ($tokens.Count -ne 256) {
    throw "EDID must contain exactly 256 bytes; found $($tokens.Count)."
}

$edid = New-Object 'System.Byte[]' 256
for ($i = 0; $i -lt 256; $i++) {
    if ($tokens[$i] -notmatch '^[0-9A-Fa-f]{2}$') {
        throw "Invalid EDID byte $i`: $($tokens[$i])"
    }
    $edid[$i] = [Convert]::ToByte($tokens[$i], 16)
}

if (($edid[0..7] -join ',') -ne '0,255,255,255,255,255,255,0' -or
    $edid[126] -ne 1 -or $edid[128] -ne 2 -or $edid[129] -ne 3 -or
    $edid[133] -ne 0x84) {
    throw 'EDID header, CTA extension, or native 720p60 VIC is invalid.'
}
for ($block = 0; $block -lt 2; $block++) {
    $sum = 0
    for ($i = $block * 128; $i -lt ($block + 1) * 128; $i++) {
        $sum += $edid[$i]
    }
    if (($sum % 256) -ne 0) {
        throw "EDID block $block has an invalid checksum."
    }
}

$sourceText = [System.IO.File]::ReadAllText($receiverSource)
for ($i = 0; $i -lt 256; $i++) {
    $address = '{0:X4}' -f (0x0D00 + $i)
    $pattern = "(?i)(16'h$address,\s*8'h)[0-9A-F]{2}"
    $count = [regex]::Matches($sourceText, $pattern).Count
    $expectedCount = if ($i -lt 8) { 2 } else { 1 }
    if ($count -ne $expectedCount) {
        throw "Vendor EDID table at $address changed: expected $expectedCount entries, found $count."
    }
    $value = '{0:X2}' -f $edid[$i]
    $sourceText = [regex]::Replace($sourceText, $pattern, ('${1}' + $value))
}

[System.IO.File]::WriteAllText(
    $receiverSource,
    $sourceText,
    (New-Object System.Text.UTF8Encoding($false))
)
Write-Host "Applied 720p60-only EDID to $receiverSource"

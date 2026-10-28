param(
    [ValidateRange(0, 65535)][int]$Sequence = 1,
    [bool]$PoseValid = $true,
    [string[]]$Words
)

$ErrorActionPreference = 'Stop'
if (-not $Words) {
    $Words = @('00010000','00000000','00000000',
               '00000000','00010000','00000000',
               '00000000','00000000','40000000')
}
if ($Words.Count -ne 9) { throw 'Provide exactly nine 32-bit coefficient words in row-major order.' }

$payload = [System.Collections.Generic.List[byte]]::new()
foreach ($word in $Words) {
    $normalized = $word -replace '^0x', ''
    if ($normalized -notmatch '^[0-9A-Fa-f]{1,8}$') {
        throw "Invalid 32-bit hexadecimal coefficient: $word"
    }
    $value = [Convert]::ToUInt32($normalized, 16)
    for ($i = 0; $i -lt 4; $i++) { $payload.Add([byte](($value -shr (8 * $i)) -band 0xFF)) }
}

$frame = [System.Collections.Generic.List[byte]]::new()
$frame.AddRange([byte[]]@(0xA5,0x5A,0x02,0x01,($Sequence -band 0xFF), (($Sequence -shr 8) -band 0xFF), $(if ($PoseValid) { 1 } else { 0 })))
$frame.AddRange($payload.ToArray())
for ($i = 0; $i -lt 20; $i++) { $frame.Add([byte]0) }
$crcType = 'Stage8PacketTools.Crc16CcittFalse' -as [type]
if (-not $crcType) {
    Add-Type -TypeDefinition @'
namespace Stage8PacketTools {
    public static class Crc16CcittFalse {
        public static ushort Compute(byte[] data, int offset, int count) {
            uint crc = 0xFFFF;
            for (int i = offset; i < offset + count; i++) {
                crc ^= ((uint)data[i]) << 8;
                for (int bit = 0; bit < 8; bit++)
                    crc = ((crc & 0x8000) != 0) ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
            }
            return (ushort)crc;
        }
    }
}
'@
}
$crc = [Stage8PacketTools.Crc16CcittFalse]::Compute($frame.ToArray(), 2, 61)
$knownCheck = [System.Text.Encoding]::ASCII.GetBytes('123456789')
if ([Stage8PacketTools.Crc16CcittFalse]::Compute($knownCheck, 0, $knownCheck.Length) -ne 0x29B1) {
    throw 'CRC-16/CCITT-FALSE known-answer check failed.'
}
$frame.Add([byte](($crc -shr 8) -band 0xFF))
$frame.Add([byte]($crc -band 0xFF))
if ($frame.Count -ne 65) { throw "Internal error: generated $($frame.Count) bytes, expected 65." }
if (-not $PSBoundParameters.ContainsKey('Words') -and $Sequence -eq 1 -and $PoseValid -and $crc -ne 0xE170) {
    throw ('Identity packet CRC self-check failed: expected E170, got {0:X4}.' -f $crc)
}

($frame | ForEach-Object { $_.ToString('X2') }) -join ' '

param(
    [string]$Com = 'COM7',
    [ValidateRange(0, 65535)][int]$Sequence = 2
)

$ErrorActionPreference = 'Stop'
$packetBuilder = Join-Path $PSScriptRoot 'Build-UartPacket.ps1'
$words = @(
    '0000DDB4', '00008000', 'FFA1BE66',
    'FFFF8000', '0000DDB4', '01703B19',
    '00000000', '00000000', '40000000'
)

$hex = & $packetBuilder -Sequence $Sequence -Words $words
$tx = [byte[]]@($hex -split '\s+' | ForEach-Object { [Convert]::ToByte($_, 16) })
if ($tx.Length -ne 65) {
    throw "Request length mismatch: got $($tx.Length) bytes, expected 65."
}

$port = [System.IO.Ports.SerialPort]::new($Com, 115200, 'None', 8, 'One')
$port.ReadTimeout = 5000
try {
    $port.Open()
    $port.DiscardInBuffer()
    $port.Write($tx, 0, $tx.Length)

    $rx = New-Object byte[] 65
    $count = 0
    while ($count -lt $rx.Length) {
        $count += $port.Read($rx, $count, $rx.Length - $count)
    }

    'RX: ' + (($rx | ForEach-Object { $_.ToString('X2') }) -join ' ')
    if ($rx[0] -ne 0xA5 -or $rx[1] -ne 0x5A -or
        $rx[2] -ne 0x02 -or $rx[3] -ne 0x81) {
        throw 'Response header or protocol version mismatch.'
    }

    $responseSequence = ([int]$rx[4]) -bor (([int]$rx[5]) -shl 8)
    if ($responseSequence -ne $Sequence) {
        throw "Response sequence mismatch: got $responseSequence, expected $Sequence."
    }
    $expectedCrc = [Stage8PacketTools.Crc16CcittFalse]::Compute($rx, 2, 61)
    $receivedCrc = ([int]$rx[63] -shl 8) -bor [int]$rx[64]
    if ($receivedCrc -ne $expectedCrc) {
        throw ('Response CRC mismatch: got 0x{0:X4}, expected 0x{1:X4}.' -f $receivedCrc, $expectedCrc)
    }
    if ($rx[6] -ne 0) {
        throw ('FPGA rejected the request with status 0x{0:X2}.' -f $rx[6])
    }
    for ($i = 0; $i -lt 56; $i++) {
        if ($rx[7 + $i] -ne $tx[7 + $i]) {
            throw "Response payload mismatch at packet offset $($i + 7)."
        }
    }

    "ACK accepted: protocol=02, sequence=$responseSequence, frameLength=$($rx.Length), CRC=$($receivedCrc.ToString('X4'))"
}
finally {
    $port.Dispose()
}

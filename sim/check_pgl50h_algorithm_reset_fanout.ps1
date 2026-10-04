param(
    [string]$ControlSetReport = (Join-Path $PSScriptRoot "..\boards\pgl50h\pds\pgl50h_rtl_synth\synthesize\pgl50h_board_top_controlsets.txt"),
    [int]$MaxMonolithicFanout = 64,
    [int]$MaxAlgorithmLeafFanout = 256,
    [int]$MaxGeometryLeafFanout = 128
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ControlSetReport)) {
    throw "FAIL: PDS control-set report not found: $ControlSetReport"
}

$resetRows = @()
foreach ($line in Get-Content -LiteralPath $ControlSetReport) {
    if ($line -match '^\s*(?<signal>[^:]+algorithm_system[^:]*?(?:rst|reset)[^:]*)\s*:\s*(?<fanout>\d+)\s*$') {
        $resetRows += [pscustomobject]@{
            Signal = $matches['signal'].Trim()
            Fanout = [int]$matches['fanout']
        }
    }
}

if ($resetRows.Count -eq 0) {
    throw "FAIL: no algorithm reset rows were found in $ControlSetReport"
}

$monolithicRows = $resetRows | Where-Object {
    $_.Signal -match '(~?algorithm_system\.core_rst_n|~?algorithm_system\.rst_n)'
}
foreach ($row in $monolithicRows) {
    if ($row.Fanout -gt $MaxMonolithicFanout) {
        throw "FAIL: monolithic algorithm reset '$($row.Signal)' has fanout $($row.Fanout), expected <= $MaxMonolithicFanout"
    }
}

$geometryRows = $resetRows | Where-Object { $_.Signal -match 'geometry_rst_n' }
foreach ($row in $geometryRows) {
    if ($row.Fanout -gt $MaxGeometryLeafFanout) {
        throw "FAIL: geometry reset leaf '$($row.Signal)' has fanout $($row.Fanout), expected <= $MaxGeometryLeafFanout"
    }
}

$oversizedLeaf = $resetRows | Where-Object {
    $_.Signal -notmatch 'geometry_rst_n' -and $_.Fanout -gt $MaxAlgorithmLeafFanout
}
if ($oversizedLeaf) {
    $detail = ($oversizedLeaf | ForEach-Object { "$($_.Signal)=$($_.Fanout)" }) -join '; '
    throw "FAIL: algorithm reset leaf fanout exceeds ${MaxAlgorithmLeafFanout}: $detail"
}

$resetRows | Sort-Object Fanout -Descending | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "PASS: PGL50H algorithm reset fanout is within acceptance limits."

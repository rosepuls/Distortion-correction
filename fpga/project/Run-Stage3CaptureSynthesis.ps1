param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage3_frame_pool_test'),
    [string]$PdsShell
)

$ErrorActionPreference = 'Stop'
if (-not $PdsShell) {
    $command = Get-Command pds_shell.exe -ErrorAction SilentlyContinue
    if ($command) {
        $PdsShell = $command.Source
    } elseif ($env:PANGO_LICENSE_FILE) {
        $PdsShell = Join-Path (Split-Path -Parent $env:PANGO_LICENSE_FILE) 'bin\pds_shell.exe'
    }
}
if (-not $PdsShell -or -not (Test-Path -LiteralPath $PdsShell -PathType Leaf)) {
    throw 'PDS shell not found. Pass -PdsShell with its absolute path.'
}

Push-Location $ProjectDirectory
try {
    $logFile = 'capture-synthesize-console.log'
    & $PdsShell -project HDMI_IN_DDR3_HDMI_OUT.pds -run synthesize *> $logFile
    if ($LASTEXITCODE -ne 0 -or
        (Select-String -LiteralPath $logFile -Pattern '^E:' -Quiet) -or
        -not (Select-String -LiteralPath $logFile -Pattern 'Action synthesize:' -Quiet)) {
        throw "PDS capture synthesis failed; inspect $logFile."
    }

    $netlist = 'synthesize\HDMI_IN_DDR3_HDMI_OUT_top_syn.vm'
    if (-not (Test-Path -LiteralPath $netlist -PathType Leaf)) {
        throw "PDS capture netlist not found: $netlist"
    }
    foreach ($instance in @(
        'frame_pool_manager capture_pool',
        'capture_frame_admission admission',
        'capture_pixel_gate pixel_gate',
        'ddr_write_drain_tracker write_tracker'
    )) {
        if (-not (Select-String -LiteralPath $netlist -SimpleMatch $instance -Quiet)) {
            throw "Capture netlist is missing $instance."
        }
    }
    Write-Host 'PASS: PDS synthesized the Stage 3 capture-to-display video top.'
} finally {
    Pop-Location
}

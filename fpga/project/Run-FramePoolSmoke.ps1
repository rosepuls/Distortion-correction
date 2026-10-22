param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage3_frame_pool_test'),
    [ValidateSet('pools', 'pipeline')]
    [string]$Target = 'pools',
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
    $projectFile = if ($Target -eq 'pipeline') { 'frame_pipeline_smoke.pds' } else { 'frame_pool_smoke.pds' }
    $topName = if ($Target -eq 'pipeline') { 'frame_pipeline_smoke_top' } else { 'frame_pool_pair_smoke_top' }
    $logFile = if ($Target -eq 'pipeline') { 'pipeline-synthesize-console.log' } else { 'smoke-synthesize-console.log' }
    & $PdsShell -project $projectFile -run synthesize *> $logFile
    if ($LASTEXITCODE -ne 0) { throw 'PDS synthesis process failed.' }
    if (Select-String -LiteralPath $logFile -Pattern '^E:' -Quiet) {
        throw "PDS synthesis logged errors; inspect $logFile."
    }
    if (-not (Select-String -LiteralPath $logFile -Pattern 'Action synthesize:' -Quiet)) {
        throw 'PDS synthesis did not reach its completion summary.'
    }

    $netlist = Join-Path $ProjectDirectory "synthesize\$($topName)_syn.vm"
    if (-not (Test-Path -LiteralPath $netlist) -or
        -not (Select-String -LiteralPath $netlist -Pattern 'capture_pool' -Quiet) -or
        -not (Select-String -LiteralPath $netlist -Pattern 'output_pool' -Quiet) -or
        -not (Select-String -LiteralPath $netlist -Pattern 'frame_pool_address address_map' -Quiet)) {
        throw 'Synthesized netlist is missing a frame pool or the address mapper.'
    }
    if ($Target -eq 'pipeline' -and
        (-not (Select-String -LiteralPath $netlist -Pattern 'frame_pipeline_ownership ownership' -Quiet) -or
         -not (Select-String -LiteralPath $netlist -Pattern 'ddr_read_burst_arbiter read_arbiter' -Quiet) -or
         -not (Select-String -LiteralPath $netlist -Pattern 'ddr_write_drain_tracker write_tracker' -Quiet) -or
         -not (Select-String -LiteralPath $netlist -Pattern 'capture_frame_admission admission' -Quiet) -or
         -not (Select-String -LiteralPath $netlist -Pattern 'capture_pixel_gate pixel_gate' -Quiet))) {
        throw 'Synthesized netlist is missing a pipeline control module.'
    }
    Write-Host "PASS: PDS synthesized $Target target."
} finally {
    Pop-Location
}

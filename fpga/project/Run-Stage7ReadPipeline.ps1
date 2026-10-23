param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage7_read_pipeline_16x8'),
    [string]$PdsShell = 'D:\Pango\PDS_2022.2-SP6.4\bin\pds_shell.exe'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ProjectDirectory -PathType Container)) {
    throw "Project missing: $ProjectDirectory"
}
if (-not (Test-Path -LiteralPath $PdsShell -PathType Leaf)) {
    throw "PDS shell missing: $PdsShell"
}

Push-Location $ProjectDirectory
try {
    $resolved = (Resolve-Path -LiteralPath '.').Path
    $log = 'stage7-read-pipeline-build.log'
    & $PdsShell -project HDMI_IN_DDR3_HDMI_OUT.pds -run gen_bit_stream *> $log
    if ($LASTEXITCODE -ne 0 -or
        (Select-String -LiteralPath $log -Pattern '^E:' -Quiet) -or
        -not (Select-String -LiteralPath $log -Pattern '^Core Insertion Complete' -Quiet) -or
        -not (Select-String -LiteralPath $log -Pattern 'Action from compile to gen_bit_stream:' -Quiet)) {
        throw "Stage 7 read-pipeline PDS flow failed: $(Join-Path $resolved $log)"
    }
    $bit = 'generate_bitstream\HDMI_IN_DDR3_HDMI_OUT_top.sbit'
    $ficSource = 'synthesize\HDMI_IN_DDR3_HDMI_OUT_top_syn.fic'
    $fic = 'generate_bitstream\HDMI_IN_DDR3_HDMI_OUT_top.fic'
    $timing = 'report_timing\HDMI_IN_DDR3_HDMI_OUT_top.rtr'
    foreach ($required in @($bit, $ficSource, $timing)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Missing build artifact: $required"
        }
    }
    if (-not (Select-String -LiteralPath $timing -Pattern 'Design Summary : All Constraints Met' -Quiet)) {
        throw "Timing constraints failed: $(Join-Path $resolved $timing)"
    }

    $ficSourcePath = Join-Path $resolved $ficSource
    $ficPath = Join-Path $resolved $fic
    Copy-Item -LiteralPath $ficSourcePath -Destination $ficPath -Force
    $ficText = [IO.File]::ReadAllText($ficPath, [Text.Encoding]::UTF8)
    $labelMap = @{
        'fram_buf/perf_coord_stall_cycles' = 'fram_buf/perf_read_arbiter_wait_cycles'
        'fram_buf/perf_read_ar_wait_cycles' = 'fram_buf/perf_read_arready_wait_cycles'
        'fram_buf/perf_read_response_wait_cycles' = 'fram_buf/perf_read_first_beat_wait_cycles'
        'fram_buf/perf_write_wait_cycles' = 'fram_buf/perf_read_interbeat_wait_cycles'
    }
    foreach ($oldLabel in $labelMap.Keys) {
        $newLabel = $labelMap[$oldLabel]
        if ($ficText.Contains($oldLabel)) {
            $ficText = $ficText.Replace($oldLabel, $newLabel)
        } elseif (-not $ficText.Contains($newLabel)) {
            throw "Expected FIC bus label missing: $oldLabel or $newLabel"
        }
    }
    [IO.File]::WriteAllText($ficPath, $ficText, [Text.UTF8Encoding]::new($false))

    Write-Host 'PASS: Stage 7 read-pipeline bitstream generated and timing met.'
    Write-Host "BITSTREAM: $(Join-Path $resolved $bit)"
    Write-Host "BITSTREAM_SHA256: $((Get-FileHash -LiteralPath $bit -Algorithm SHA256).Hash)"
    Write-Host "FIC: $(Join-Path $resolved $fic)"
    Write-Host "FIC_SHA256: $((Get-FileHash -LiteralPath $ficPath -Algorithm SHA256).Hash)"
} finally {
    Pop-Location
}

param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage5_identity_fps_debug'),
    [string]$PdsShell = 'D:\Pango\PDS_2022.2-SP6.4\bin\pds_shell.exe'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ProjectDirectory -PathType Container)) { throw "Project missing: $ProjectDirectory" }
if (-not (Test-Path -LiteralPath $PdsShell -PathType Leaf)) { throw "PDS shell missing: $PdsShell" }
Push-Location $ProjectDirectory
try {
    $resolved = (Resolve-Path -LiteralPath '.').Path
    $log = 'stage5-fps-debug-build.log'
    & $PdsShell -project HDMI_IN_DDR3_HDMI_OUT.pds -run gen_bit_stream *> $log
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern '^E:' -Quiet) -or
        -not (Select-String -LiteralPath $log -Pattern 'Core Insertion Complete' -Quiet) -or
        -not (Select-String -LiteralPath $log -Pattern 'Action from compile to gen_bit_stream:' -Quiet)) {
        throw "Stage 5 diagnostic PDS flow failed: $(Join-Path $resolved $log)"
    }
    $bit = 'generate_bitstream\HDMI_IN_DDR3_HDMI_OUT_top.sbit'
    $ficSource = 'synthesize\HDMI_IN_DDR3_HDMI_OUT_top_syn.fic'
    $fic = 'generate_bitstream\HDMI_IN_DDR3_HDMI_OUT_top.fic'
    $timing = 'report_timing\HDMI_IN_DDR3_HDMI_OUT_top.rtr'
    foreach ($required in @($bit, $ficSource, $timing)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing build artifact: $required" }
    }
    if (-not (Select-String -LiteralPath $timing -Pattern 'Design Summary : All Constraints Met' -Quiet)) {
        throw "Timing failed: $(Join-Path $resolved $timing)"
    }
    Copy-Item -LiteralPath $ficSource -Destination $fic -Force
    Write-Host 'PASS: Stage 5 FPS diagnostic bitstream and matching FIC generated with timing met.'
    Write-Host "BITSTREAM: $(Join-Path $resolved $bit)"
    Write-Host "BITSTREAM_SHA256: $((Get-FileHash -LiteralPath $bit -Algorithm SHA256).Hash)"
    Write-Host "FIC: $(Join-Path $resolved $fic)"
    Write-Host "FIC_SHA256: $((Get-FileHash -LiteralPath $fic -Algorithm SHA256).Hash)"
} finally { Pop-Location }

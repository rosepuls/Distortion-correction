param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage5_identity_ddr'),
    [string]$PdsShell = 'D:\Pango\PDS_2022.2-SP6.4\bin\pds_shell.exe'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PdsShell -PathType Leaf)) { throw "PDS shell not found: $PdsShell" }
if (-not (Test-Path -LiteralPath $ProjectDirectory -PathType Container)) { throw "Project not found: $ProjectDirectory" }
Push-Location $ProjectDirectory
try {
    $resolvedProject = (Resolve-Path -LiteralPath '.').Path
    $log = 'stage5-gen-bitstream-console.log'
    & $PdsShell -project HDMI_IN_DDR3_HDMI_OUT.pds -run gen_bit_stream *> $log
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern '^E:' -Quiet) -or
        -not (Select-String -LiteralPath $log -Pattern 'Action from compile to gen_bit_stream:' -Quiet)) {
        throw "Stage 5 PDS flow failed; inspect $(Join-Path $resolvedProject $log)"
    }
    $bitstream = 'generate_bitstream\HDMI_IN_DDR3_HDMI_OUT_top.sbit'
    $timing = 'report_timing\HDMI_IN_DDR3_HDMI_OUT_top.rtr'
    if (-not (Test-Path -LiteralPath $bitstream -PathType Leaf)) { throw "Bitstream missing: $bitstream" }
    if (-not (Test-Path -LiteralPath $timing -PathType Leaf)) { throw "Timing report missing: $timing" }
    if (-not (Select-String -LiteralPath $timing -Pattern 'All Constraints Met' -Quiet)) {
        throw "Timing constraints are not met; inspect $(Join-Path $resolvedProject $timing)"
    }
    $hash = (Get-FileHash -LiteralPath $bitstream -Algorithm SHA256).Hash
    Write-Host 'PASS: Stage 5 bitstream generated with all timing constraints met.'
    Write-Host "BITSTREAM: $(Join-Path $resolvedProject $bitstream)"
    Write-Host "SHA256: $hash"
} finally {
    Pop-Location
}

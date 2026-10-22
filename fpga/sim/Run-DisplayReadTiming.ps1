param(
    [Parameter(Mandatory=$true)][string]$ReaderRtl,
    [switch]$InjectCounterSkew,
    [ValidateRange(12,720)][int]$FrameLines = 12,
    [string]$VivadoHome = 'D:\Xilinx\Vivado\2020.2'
)

$ErrorActionPreference = 'Stop'
$reader = (Resolve-Path -LiteralPath $ReaderRtl).Path
$adapter = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\rtl\memory\display_read_adapter.v')).Path
$testbench = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'display_read_timing_tb.v')).Path
$workDir = Join-Path $PSScriptRoot ('.work\display_read_timing-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
$testbenchText = [System.IO.File]::ReadAllText($testbench)
$frameAnchor = 'parameter FRAME_LINES = 12;'
if (-not $testbenchText.Contains($frameAnchor)) { throw 'Frame count parameter not found.' }
$testbench = Join-Path $workDir 'display_read_timing_tb.v'
[System.IO.File]::WriteAllText($testbench,
    $testbenchText.Replace($frameAnchor, "parameter FRAME_LINES = $FrameLines;"))
if ($InjectCounterSkew) {
    # Model unequal clock-to-Q/routing delay at a binary counter carry. This
    # changes no stable counter value and adds no DDR delay. A source-registered
    # Gray output must isolate the destination from the intermediate binary bus.
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    $readerText = $latin1.GetString([System.IO.File]::ReadAllBytes($reader))
    $anchor = "consumed_beats <= consumed_beats + 1'b1;"
    if (-not $readerText.Contains($anchor)) { throw 'Counter skew injection anchor not found.' }
    $skewedIncrement = @'
begin
                consumed_beats[8:0] <= #0.1 consumed_beats[8:0] + 9'd1;
                consumed_beats[9] <= #2.1
                    consumed_beats[9] ^ (&consumed_beats[8:0]);
            end
'@
    $reader = Join-Path $workDir 'rd_buf_counter_skew.v'
    [System.IO.File]::WriteAllBytes($reader, $latin1.GetBytes(
        $readerText.Replace($anchor, $skewedIncrement)))
}
Write-Host "Display timing simulation logs: $workDir"
Push-Location $workDir
try {
    & (Join-Path $VivadoHome 'bin\xvlog.bat') --sv --work work --log xvlog.log $adapter $reader $testbench
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & (Join-Path $VivadoHome 'bin\xelab.bat') work.display_read_timing_tb -s display_read_timing_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & (Join-Path $VivadoHome 'bin\xsim.bat') display_read_timing_sim -runall --log xsim.log
    $simExit = $LASTEXITCODE
    if ($simExit -ne 0 -or
        (Select-String -LiteralPath xsim.log -Pattern 'FAIL:' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: two display frames cross Gray pointer wrap and frame rebase without underrun' -Quiet)) {
        throw 'Display read timing test failed.'
    }
} finally {
    Pop-Location
}

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\distortion_core_optimized_unit'
$vectorDirectory = Join-Path $runDirectory 'vectors'
New-Item -ItemType Directory -Force -Path $vectorDirectory | Out-Null
$vectorCopy = Join-Path $vectorDirectory 'distortion_core_optimized_q18.txt'
if (-not (Test-Path $vectorCopy)) {
    Copy-Item `
        (Join-Path $projectRoot 'vectors\distortion_core_optimized_q18.txt') `
        $vectorCopy
}

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot 'rtl\distortion\coordinate_split.sv') `
        (Join-Path $projectRoot 'rtl\distortion\distortion_core_optimized.sv') `
        (Join-Path $projectRoot 'sim\tb_distortion_core_optimized.sv') `
        (Join-Path $projectRoot 'sim\tb_distortion_core_optimized_stream.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_distortion_core_optimized -s distortion_core_optimized_unit_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $goldenOutput = & xsim distortion_core_optimized_unit_sim -runall 2>&1
    $goldenExitCode = $LASTEXITCODE
    $goldenOutput | Write-Output
    if ($goldenExitCode -ne 0) { exit $goldenExitCode }
    if (($goldenOutput | Out-String) -notmatch 'TEST_PASS: distortion_core_optimized golden_vectors') {
        throw 'Golden-vector simulation completed without its pass marker.'
    }

    & xelab tb_distortion_core_optimized_stream -s distortion_core_optimized_stream_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $streamOutput = & xsim distortion_core_optimized_stream_sim -runall 2>&1
    $streamExitCode = $LASTEXITCODE
    $streamOutput | Write-Output
    if ($streamExitCode -ne 0) { exit $streamExitCode }
    if (($streamOutput | Out-String) -notmatch 'TEST_PASS: distortion_core_optimized_stream') {
        throw 'Streaming simulation completed without its pass marker.'
    }
}
finally {
    Pop-Location
}

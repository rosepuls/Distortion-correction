$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\coordinate_fifo'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot 'rtl\platform\common\memory\coordinate_fifo.sv') `
        (Join-Path $projectRoot 'sim\tb_coordinate_fifo.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_coordinate_fifo -s coordinate_fifo_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & xsim coordinate_fifo_sim -runall 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: coordinate_fifo') {
        throw 'XSim completed without the expected coordinate_fifo pass marker.'
    }
}
finally {
    Pop-Location
}

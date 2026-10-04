$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\ddr_burst_reader'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot 'rtl\platform\common\memory\ddr_burst_reader.sv') `
        (Join-Path $projectRoot 'sim\tb_ddr_burst_reader.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_ddr_burst_reader -s ddr_burst_reader_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & xsim ddr_burst_reader_sim -runall 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: ddr_burst_reader') {
        throw 'XSim completed without the expected ddr_burst_reader pass marker.'
    }
}
finally {
    Pop-Location
}

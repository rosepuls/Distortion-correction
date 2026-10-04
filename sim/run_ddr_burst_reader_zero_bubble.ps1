$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\ddr_burst_reader_zero_bubble'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot 'rtl\platform\common\memory\ddr_burst_reader.sv') `
        (Join-Path $projectRoot 'sim\tb_ddr_burst_reader_zero_bubble.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & xelab tb_ddr_burst_reader_zero_bubble -s ddr_burst_reader_zero_bubble_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $simOutput = & xsim ddr_burst_reader_zero_bubble_sim -runall 2>&1
    $simOutput | Write-Output
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: ddr_burst_reader_zero_bubble') {
        throw 'XSim completed without the expected zero-bubble pass marker.'
    }
}
finally {
    Pop-Location
}

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\ddr3_pixel_read_adapter'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot 'rtl\board\pgl50h\ddr3_pixel_read_adapter.sv') `
        (Join-Path $projectRoot 'sim\tb_ddr3_pixel_read_adapter.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_ddr3_pixel_read_adapter -s ddr3_pixel_read_adapter_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & xsim ddr3_pixel_read_adapter_sim -runall 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: ddr3_pixel_read_adapter') {
        throw 'XSim completed without the expected ddr3_pixel_read_adapter pass marker.'
    }
}
finally {
    Pop-Location
}

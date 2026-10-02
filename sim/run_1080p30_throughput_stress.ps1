$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\1080p30_throughput_stress'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    & xvlog -sv -d STRESS_DDR `
        (Join-Path $projectRoot 'rtl\memory\ddr_burst_reader.sv') `
        (Join-Path $projectRoot 'rtl\memory\pixel_tile_cache.sv') `
        (Join-Path $projectRoot 'rtl\interpolation\bilinear_interp.sv') `
        (Join-Path $projectRoot 'rtl\memory\cached_pixel_fetch_engine.sv') `
        (Join-Path $projectRoot 'sim\tb_1080p30_throughput.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_1080p30_throughput -s throughput_1080p30_stress_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & xsim throughput_1080p30_stress_sim -runall 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: 1080p30_throughput') {
        throw 'XSim completed without the expected stressed 1080p30 throughput marker.'
    }
}
finally {
    Pop-Location
}

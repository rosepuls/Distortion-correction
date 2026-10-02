$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\cached_pixel_fetch_engine'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot 'rtl\memory\coordinate_fifo.sv') `
        (Join-Path $projectRoot 'rtl\memory\ddr_burst_reader.sv') `
        (Join-Path $projectRoot 'rtl\memory\pixel_tile_cache.sv') `
        (Join-Path $projectRoot 'rtl\interpolation\bilinear_interp.sv') `
        (Join-Path $projectRoot 'rtl\memory\cached_pixel_fetch_engine.sv') `
        (Join-Path $projectRoot 'sim\tb_cached_pixel_fetch_engine.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_cached_pixel_fetch_engine -s cached_pixel_fetch_engine_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & xsim cached_pixel_fetch_engine_sim -runall 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: cached_pixel_fetch_engine') {
        throw 'XSim completed without the expected cached_pixel_fetch_engine pass marker.'
    }
}
finally {
    Pop-Location
}

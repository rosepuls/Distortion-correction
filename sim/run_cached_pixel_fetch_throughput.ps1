$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\cached_pixel_fetch_throughput'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot 'rtl\platform\common\memory\ddr_burst_reader.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\pixel_tile_cache.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\tile_cache_bank_ram.sv') `
        (Join-Path $projectRoot 'sim\pgl50h_tile_cache_bank_ip_model.sv') `
        (Join-Path $projectRoot 'rtl\algorithm\interpolation\bilinear_interp.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\cached_pixel_fetch_engine.sv') `
        (Join-Path $projectRoot 'sim\tb_cached_pixel_fetch_throughput.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_cached_pixel_fetch_throughput -s cached_pixel_fetch_throughput_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & xsim cached_pixel_fetch_throughput_sim -runall 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: cached_pixel_fetch_throughput') {
        throw 'XSim completed without the expected throughput pass marker.'
    }
}
finally {
    Pop-Location
}

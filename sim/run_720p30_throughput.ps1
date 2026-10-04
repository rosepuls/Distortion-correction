$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\throughput_720p30'
New-Item -ItemType Directory -Force $runDirectory | Out-Null
Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot 'rtl\algorithm\interpolation\bilinear_interp.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\ddr_burst_reader.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\pixel_tile_cache.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\tile_cache_bank_ram.sv') `
        (Join-Path $projectRoot 'sim\pgl50h_tile_cache_bank_ip_model.sv') `
        (Join-Path $projectRoot 'rtl\platform\common\memory\cached_pixel_fetch_engine.sv') `
        (Join-Path $projectRoot 'sim\tb_720p30_throughput.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & xelab tb_720p30_throughput -s throughput_720p30_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $simOutput = & xsim throughput_720p30_sim -runall 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: 720p30_throughput') {
        throw 'XSim completed without the expected 720p30 throughput pass marker.'
    }
}
finally {
    Pop-Location
}

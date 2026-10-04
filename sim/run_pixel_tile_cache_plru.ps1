$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\pixel_tile_cache_plru'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot 'rtl\platform\common\memory\pixel_tile_cache.sv') `
        (Join-Path $projectRoot 'sim\tb_pixel_tile_cache_plru.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_pixel_tile_cache_plru -s pixel_tile_cache_plru_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & xsim pixel_tile_cache_plru_sim -runall 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: pixel_tile_cache_plru') {
        throw 'XSim completed without the expected pixel_tile_cache_plru pass marker.'
    }
}
finally {
    Pop-Location
}

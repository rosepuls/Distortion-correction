$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\tile_cache_bank_ram'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot 'rtl\platform\common\memory\tile_cache_bank_ram.sv') `
        (Join-Path $projectRoot 'sim\pgl50h_tile_cache_bank_ip_model.sv') `
        (Join-Path $projectRoot 'sim\tb_tile_cache_bank_ram.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_tile_cache_bank_ram -s tile_cache_bank_ram_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & xsim tile_cache_bank_ram_sim -runall 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: tile_cache_bank_ram') {
        throw 'XSim completed without the expected tile_cache_bank_ram pass marker.'
    }
}
finally {
    Pop-Location
}

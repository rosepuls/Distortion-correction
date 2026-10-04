$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\algorithm_frame_writer_rgbx'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot 'rtl\board\pgl50h\algorithm_frame_writer_rgbx.sv') `
        (Join-Path $projectRoot 'sim\tb_algorithm_frame_writer_rgbx.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_algorithm_frame_writer_rgbx -s algorithm_frame_writer_rgbx_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & xsim algorithm_frame_writer_rgbx_sim -runall 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: algorithm_frame_writer_rgbx') {
        throw 'XSim completed without the expected RGBX writer pass marker.'
    }
}
finally {
    Pop-Location
}

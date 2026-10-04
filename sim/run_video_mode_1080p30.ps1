$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runDirectory = Join-Path $projectRoot 'xsim.dir\video_mode_1080p30'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    & xvlog -sv `
        (Join-Path $projectRoot 'rtl\board\pgl50h\video_mode_1080p30.sv') `
        (Join-Path $projectRoot 'sim\tb_video_mode_1080p30.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & xelab tb_video_mode_1080p30 -s video_mode_1080p30_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & xsim video_mode_1080p30_sim -runall 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: video_mode_1080p30') {
        throw 'XSim completed without the expected video_mode_1080p30 pass marker.'
    }
}
finally {
    Pop-Location
}

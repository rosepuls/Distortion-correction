$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$vivadoRoot = 'D:\Xilinx\Vivado\2020.2'
$runDirectory = Join-Path $projectRoot 'xsim.dir\realtime_frame_scheduler'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    & "$vivadoRoot\bin\xvlog.bat" -sv `
        (Join-Path $projectRoot 'rtl\board\pgl50h\realtime_frame_scheduler.sv') `
        (Join-Path $projectRoot 'sim\tb_realtime_frame_scheduler.sv')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & "$vivadoRoot\bin\xelab.bat" tb_realtime_frame_scheduler -s realtime_frame_scheduler_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & "$vivadoRoot\bin\xsim.bat" realtime_frame_scheduler_sim -R 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: realtime_frame_scheduler') {
        throw 'XSim completed without the expected realtime_frame_scheduler pass marker.'
    }
}
finally {
    Pop-Location
}

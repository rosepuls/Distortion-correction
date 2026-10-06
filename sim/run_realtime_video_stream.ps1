$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$vivadoRoot = 'D:\Xilinx\Vivado\2020.2'
$runDirectory = Join-Path $projectRoot 'xsim.dir\realtime_video_stream'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
Push-Location $runDirectory
try {
    & (Join-Path $vivadoRoot 'bin\xvlog.bat') -sv `
        (Join-Path $projectRoot 'rtl\board\pgl50h\realtime_frame_scheduler.sv') `
        (Join-Path $projectRoot 'sim\models\realtime_video_stream_harness.sv') `
        (Join-Path $projectRoot 'sim\tb_realtime_video_stream.sv')
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed: $LASTEXITCODE" }
    & (Join-Path $vivadoRoot 'bin\xelab.bat') tb_realtime_video_stream -s realtime_video_stream_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab failed: $LASTEXITCODE" }
    $simOutput = & (Join-Path $vivadoRoot 'bin\xsim.bat') realtime_video_stream_sim -R 2>&1
    $simOutput | Write-Output
    if ($LASTEXITCODE -ne 0) { throw "xsim failed: $LASTEXITCODE" }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: realtime_video_stream') {
        throw 'XSim completed without the expected realtime_video_stream pass marker.'
    }
} finally {
    Pop-Location
}

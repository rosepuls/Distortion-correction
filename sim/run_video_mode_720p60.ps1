$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$vivadoRoot = 'D:\Xilinx\Vivado\2020.2'
$runDirectory = Join-Path $projectRoot 'xsim.dir\video_mode_720p60'
$rtlPath = Join-Path $projectRoot 'rtl\board\pgl50h\video_mode_720p60.sv'
$testbenchPath = Join-Path $projectRoot 'sim\tb_video_mode_720p60.sv'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

Push-Location $runDirectory
try {
    $sources = @($testbenchPath)
    if (Test-Path $rtlPath) {
        $sources = @($rtlPath, $testbenchPath)
    }
    & (Join-Path $vivadoRoot 'bin\xvlog.bat') -sv $sources
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed: $LASTEXITCODE" }

    & (Join-Path $vivadoRoot 'bin\xelab.bat') tb_video_mode_720p60 -s video_mode_720p60_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab failed: $LASTEXITCODE" }

    $simOutput = & (Join-Path $vivadoRoot 'bin\xsim.bat') video_mode_720p60_sim -R 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { throw "xsim failed: $simExitCode" }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: video_mode_720p60') {
        throw 'XSim completed without the expected video_mode_720p60 pass marker.'
    }
}
finally {
    Pop-Location
}

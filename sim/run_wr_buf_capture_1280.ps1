$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$vivadoRoot = 'D:\Xilinx\Vivado\2020.2'
$runDirectory = Join-Path $projectRoot 'xsim.dir\wr_buf_capture_1280'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

$sources = @(
    'sim/models/pg2l200h_board_vendor_stubs.sv',
    'boards/pg2l200h/pds/pg2l200h_rtl_synth/source/rtl/vendor/pg2l200h/ddr/wr_buf.v',
    'sim/tb_wr_buf_capture_1280.sv'
) | ForEach-Object { Join-Path $projectRoot $_ }

Push-Location $runDirectory
try {
    & (Join-Path $vivadoRoot 'bin\xvlog.bat') -sv -d USE_VENDOR_WR_BUF @sources
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & (Join-Path $vivadoRoot 'bin\xelab.bat') tb_wr_buf_capture_1280 -s wr_buf_capture_1280_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & (Join-Path $vivadoRoot 'bin\xsim.bat') wr_buf_capture_1280_sim -R 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: wr_buf_capture_1280') {
        throw 'XSim completed without the expected 1280-pixel capture pass marker.'
    }
}
finally {
    Pop-Location
}

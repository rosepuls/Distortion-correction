$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$vivadoRoot = 'D:\Xilinx\Vivado\2020.2'
$pangoRoot = 'D:\Pango\PDS_2022.2-SP6.4'
$runDirectory = Join-Path $projectRoot 'xsim.dir\wr_buf_capture_720'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

$sources = @(
    (Join-Path $pangoRoot 'arch\vendor\pango\verilog\simulation\GTP_GRS.v'),
    (Join-Path $pangoRoot 'arch\vendor\pango\verilog\simulation\GTP_DRM36K_E1.v'),
    'boards/pg2l200h/pds/pg2l200h_rtl_synth/ipcore/wr_fram_buf/rtl/ipm2l_sdpram_v1_10_wr_fram_buf.v',
    'boards/pg2l200h/pds/pg2l200h_rtl_synth/ipcore/wr_fram_buf/wr_fram_buf.v',
    'sim/models/pg2l200h_board_vendor_stubs.sv',
    'boards/pg2l200h/pds/pg2l200h_rtl_synth/source/rtl/vendor/pg2l200h/ddr/wr_buf.v',
    'sim/tb_wr_buf_capture_720.sv'
) | ForEach-Object { if ($_ -is [string] -and [System.IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $projectRoot $_ } }

if (-not (Test-Path (Join-Path $pangoRoot 'arch\vendor\pango\verilog\simulation\GTP_DRM36K_E1.v'))) {
    throw "Pango primitive simulation model not found under $pangoRoot"
}

Push-Location $runDirectory
try {
    & (Join-Path $vivadoRoot 'bin\xvlog.bat') -sv -d USE_VENDOR_WR_BUF -d USE_VENDOR_WR_FRAM_BUF @sources
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & (Join-Path $vivadoRoot 'bin\xelab.bat') tb_wr_buf_capture_720 -s wr_buf_capture_720_sim
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $simOutput = & (Join-Path $vivadoRoot 'bin\xsim.bat') wr_buf_capture_720_sim -R 2>&1
    $simExitCode = $LASTEXITCODE
    $simOutput | Write-Output
    if ($simExitCode -ne 0) { exit $simExitCode }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: wr_buf_capture_720') {
        throw 'XSim completed without the expected full-frame capture pass marker.'
    }
}
finally {
    Pop-Location
}

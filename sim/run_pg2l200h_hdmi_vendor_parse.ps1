$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$vivadoRoot = 'D:\Xilinx\Vivado\2020.2'
$runDirectory = Join-Path $projectRoot 'xsim.dir\pg2l200h_hdmi_vendor_parse'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

$sources = @(
    'rtl/vendor/pg2l200h/hdmi/iic_dri.v',
    'rtl/vendor/pg2l200h/hdmi/ms7200_ctl.v',
    'rtl/vendor/pg2l200h/hdmi/ms7210_ctl.v',
    'rtl/vendor/pg2l200h/hdmi/ms72xx_ctl.v'
) | ForEach-Object { Join-Path $projectRoot $_ }

Push-Location $runDirectory
try {
    & (Join-Path $vivadoRoot 'bin\xvlog.bat') @sources
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Output 'TEST_PASS: pg2l200h_hdmi_vendor_parse'
}
finally {
    Pop-Location
}

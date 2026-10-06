$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$vivadoRoot = 'D:\Xilinx\Vivado\2020.2'
$runDirectory = Join-Path $projectRoot 'xsim.dir\ddr_two_client_arbiter'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
Push-Location $runDirectory
try {
    & (Join-Path $vivadoRoot 'bin\xvlog.bat') -sv `
        (Join-Path $projectRoot 'rtl\board\pgl50h\ddr_two_client_arbiter.sv') `
        (Join-Path $projectRoot 'sim\tb_ddr_two_client_arbiter.sv')
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed: $LASTEXITCODE" }
    & (Join-Path $vivadoRoot 'bin\xelab.bat') tb_ddr_two_client_arbiter -s ddr_two_client_arbiter_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab failed: $LASTEXITCODE" }
    $simOutput = & (Join-Path $vivadoRoot 'bin\xsim.bat') ddr_two_client_arbiter_sim -R 2>&1
    $simOutput | Write-Output
    if ($LASTEXITCODE -ne 0) { throw "xsim failed: $LASTEXITCODE" }
    if (($simOutput | Out-String) -notmatch 'TEST_PASS: ddr_two_client_arbiter') {
        throw 'XSim completed without expected ddr_two_client_arbiter pass marker.'
    }
} finally {
    Pop-Location
}

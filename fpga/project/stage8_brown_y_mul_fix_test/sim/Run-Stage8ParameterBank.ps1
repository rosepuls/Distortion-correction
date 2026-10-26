param([string]$VivadoHome = 'D:\Xilinx\Vivado\2020.2')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$work = Join-Path $PSScriptRoot '.work\parameter-bank'
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & (Join-Path $VivadoHome 'bin\xvlog.bat') --sv --work work --log xvlog.log `
        (Join-Path $projectRoot 'source\rtl\correction\homography_parameter_bank.sv') `
        (Join-Path $PSScriptRoot 'homography_parameter_bank_tb.sv')
    if ($LASTEXITCODE -ne 0) { throw 'Stage 8 parameter bank xvlog failed.' }
    & (Join-Path $VivadoHome 'bin\xelab.bat') work.homography_parameter_bank_tb `
        -s homography_parameter_bank_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'Stage 8 parameter bank xelab failed.' }
    & (Join-Path $VivadoHome 'bin\xsim.bat') homography_parameter_bank_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: Stage 8 parameter bank' -Quiet)) {
        throw 'Stage 8 parameter bank simulation failed.'
    }
} finally {
    Pop-Location
}

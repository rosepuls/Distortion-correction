param([string]$VivadoHome = 'D:\Xilinx\Vivado\2020.2')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$work = Join-Path $PSScriptRoot '.work\brown-signed-correction'
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & (Join-Path $VivadoHome 'bin\xvlog.bat') --sv --work work --log xvlog.log `
        (Join-Path $projectRoot 'source\rtl\correction\fractional_brown_mapper.sv') `
        (Join-Path $PSScriptRoot 'brown_signed_correction_tb.sv')
    if ($LASTEXITCODE -ne 0) { throw 'Brown xvlog failed.' }
    & (Join-Path $VivadoHome 'bin\xelab.bat') work.brown_signed_correction_tb `
        -s brown_signed_correction_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'Brown xelab failed.' }
    & (Join-Path $VivadoHome 'bin\xsim.bat') brown_signed_correction_sim `
        -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        -not (Select-String -LiteralPath xsim.log `
            -Pattern 'PASS: Brown signed Y correction at hardware capture coordinates' -Quiet)) {
        throw 'Brown signed correction simulation failed.'
    }
} finally {
    Pop-Location
}

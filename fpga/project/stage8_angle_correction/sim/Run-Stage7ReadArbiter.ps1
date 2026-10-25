param([string]$VivadoHome = 'D:\Xilinx\Vivado\2020.2')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$work = Join-Path $PSScriptRoot '.work\read-arbiter'
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & (Join-Path $VivadoHome 'bin\xvlog.bat') --sv --work work --log xvlog.log `
        (Join-Path $projectRoot 'source\rtl\ddr_read_burst_arbiter.v') `
        (Join-Path $PSScriptRoot 'stage7_read_arbiter_tb.sv')
    if ($LASTEXITCODE -ne 0) { throw 'Stage7 read arbiter xvlog failed.' }
    & (Join-Path $VivadoHome 'bin\xelab.bat') work.stage7_read_arbiter_tb -s stage7_read_arbiter_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'Stage7 read arbiter xelab failed.' }
    & (Join-Path $VivadoHome 'bin\xsim.bat') stage7_read_arbiter_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: four outstanding' -Quiet)) {
        throw 'Stage7 read arbiter simulation failed.'
    }
} finally {
    Pop-Location
}

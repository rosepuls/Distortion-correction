param([string]$VivadoHome = 'D:\Xilinx\Vivado\2020.2')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$work = Join-Path $PSScriptRoot '.work\homography-chain'
$romDir = Join-Path $work 'source\rtl\correction'
New-Item -ItemType Directory -Path $romDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'source\rtl\correction\reciprocal_seed_q30.mem') `
    -Destination (Join-Path $romDir 'reciprocal_seed_q30.mem') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'homography_reference_vectors.mem') `
    -Destination (Join-Path $work 'homography_reference_vectors.mem') -Force
Push-Location $work
try {
    & (Join-Path $VivadoHome 'bin\xvlog.bat') --sv --work work --log xvlog.log `
        (Join-Path $projectRoot 'source\rtl\correction\homography_mapper.sv') `
        (Join-Path $projectRoot 'source\rtl\correction\fractional_brown_mapper.sv') `
        (Join-Path $projectRoot 'source\rtl\correction\bilinear_sample_planner.sv') `
        (Join-Path $PSScriptRoot 'homography_chain_tb.sv') `
        (Join-Path $PSScriptRoot 'homography_reference_tb.sv') `
        (Join-Path $PSScriptRoot 'planner_strict_border_tb.sv')
    if ($LASTEXITCODE -ne 0) { throw 'Stage 8 chain xvlog failed.' }
    & (Join-Path $VivadoHome 'bin\xelab.bat') work.homography_chain_tb `
        -s homography_chain_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'Stage 8 chain xelab failed.' }
    & (Join-Path $VivadoHome 'bin\xsim.bat') homography_chain_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: Stage 8 homography/Brown chain' -Quiet)) {
        throw 'Stage 8 chain simulation failed.'
    }
    & (Join-Path $VivadoHome 'bin\xelab.bat') work.homography_reference_tb `
        -s homography_reference_sim --log xelab-reference.log
    if ($LASTEXITCODE -ne 0) { throw 'Stage 8 reference xelab failed.' }
    & (Join-Path $VivadoHome 'bin\xsim.bat') homography_reference_sim `
        -runall --log xsim-reference.log
    if ($LASTEXITCODE -ne 0 -or
        -not (Select-String -LiteralPath xsim-reference.log `
            -Pattern 'PASS: Stage 8 60 synthetic homography/Brown reference vectors' -Quiet)) {
        throw 'Stage 8 reference simulation failed.'
    }
    & (Join-Path $VivadoHome 'bin\xelab.bat') work.planner_strict_border_tb `
        -s planner_strict_border_sim --log xelab-planner.log
    if ($LASTEXITCODE -ne 0) { throw 'Stage 8 planner xelab failed.' }
    & (Join-Path $VivadoHome 'bin\xsim.bat') planner_strict_border_sim `
        -runall --log xsim-planner.log
    if ($LASTEXITCODE -ne 0 -or
        -not (Select-String -LiteralPath xsim-planner.log `
            -Pattern 'PASS: Stage 8 strict four-neighbor black border' -Quiet)) {
        throw 'Stage 8 planner simulation failed.'
    }
} finally {
    Pop-Location
}

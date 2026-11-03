param([string]$VivadoHome = $env:VIVADO_HOME)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing Vivado tool: $tool" }
}

$project = Split-Path -Parent $PSScriptRoot
$rtl = Join-Path $project 'source\rtl\correction\scale_3_2_mapper.sv'
$testbench = Join-Path $PSScriptRoot 'scale_3_2_mapper_tb.sv'
$work = Join-Path $PSScriptRoot '.work\scale-3-2'
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & $xvlog --sv --work work --log xvlog.log $rtl $testbench
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.scale_3_2_mapper_tb -s scale_3_2_mapper_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim scale_3_2_mapper_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        (Select-String -LiteralPath xsim.log -Pattern 'FAIL' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: Stage 12 center-aligned 3:2 mapping, rounding, metadata, and backpressure' -Quiet)) {
        throw 'Stage 12 scale mapper simulation did not report PASS.'
    }
} finally { Pop-Location }

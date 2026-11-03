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
$rtl = Join-Path $project 'source\rtl\correction\adaptive_bilinear_sharpener.sv'
$testbench = Join-Path $PSScriptRoot 'adaptive_bilinear_sharpener_tb.sv'
$work = Join-Path $PSScriptRoot '.work\adaptive-sharpener'
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & $xvlog --sv --work work --log xvlog.log $rtl $testbench
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.adaptive_bilinear_sharpener_tb -s adaptive_bilinear_sharpener_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim adaptive_bilinear_sharpener_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        (Select-String -LiteralPath xsim.log -Pattern 'FAIL' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: adaptive bilinear edge compensation, contrast gate, clamp path, metadata' -Quiet)) {
        throw 'Stage 12 adaptive sharpener simulation did not report PASS.'
    }
} finally { Pop-Location }

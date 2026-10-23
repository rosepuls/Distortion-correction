param([string]$VivadoHome = $env:VIVADO_HOME)
$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing Vivado tool: $tool" }
}
$rtl = Join-Path $PSScriptRoot '..\rtl\correction'
$work = Join-Path $PSScriptRoot ('.work\pipelined-bilinear-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & $xvlog --sv --work work --log xvlog.log `
        (Join-Path $rtl 'bilinear_interpolator.sv') `
        (Join-Path $rtl 'pipelined_bilinear_interpolator.sv') `
        (Join-Path $PSScriptRoot 'pipelined_bilinear_interpolator_tb.sv')
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.pipelined_bilinear_interpolator_tb -s pipelined_bilinear_interpolator_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim pipelined_bilinear_interpolator_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        (Select-String -LiteralPath xsim.log -Pattern 'FAIL' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: pipelined bilinear interpolation matched 100 reference transactions' -Quiet)) {
        throw 'Pipelined interpolation test did not report PASS.'
    }
} finally { Pop-Location }

param([string]$VivadoHome = $env:VIVADO_HOME)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
$simDir = $PSScriptRoot
$projectRoot = Split-Path $simDir -Parent
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing $tool" }
}
$work = Join-Path $simDir ('.work\stage9-bilinear-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & $xvlog --sv --work work --log xvlog.log `
        (Join-Path $projectRoot 'source\rtl\correction\pipelined_bilinear_interpolator.sv') `
        (Join-Path $simDir 'bilinear_interpolator_mode_tb.sv')
    if ($LASTEXITCODE -ne 0) { throw 'Bilinear xvlog failed.' }
    & $xelab work.bilinear_interpolator_mode_tb -s bilinear_interpolator_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'Bilinear xelab failed.' }
    & $xsim bilinear_interpolator_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: Stage 9 bilinear fractional interpolation and backpressure' -Quiet)) {
        throw 'Bilinear interpolation simulation did not report PASS.'
    }
} finally { Pop-Location }

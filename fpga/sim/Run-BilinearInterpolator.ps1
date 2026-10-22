param(
    [string]$VivadoHome = $env:VIVADO_HOME
)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) {
    throw 'Set VIVADO_HOME or pass -VivadoHome to locate Vivado Simulator.'
}

$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Vivado Simulator tool not found: $tool"
    }
}

$simDir = $PSScriptRoot
$rtl = [System.IO.Path]::GetFullPath(
    (Join-Path $simDir '..\rtl\correction\bilinear_interpolator.sv')
)
$testbench = Join-Path $simDir 'bilinear_interpolator_tb.sv'
$workDir = Join-Path $simDir ('.work\bilinear-interpolator-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

Push-Location $workDir
try {
    & $xvlog --sv --work work --log xvlog.log $rtl $testbench
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.bilinear_interpolator_tb -s bilinear_interpolator_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim bilinear_interpolator_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed.' }
    if ((Select-String -LiteralPath xsim.log -Pattern 'FAIL' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: bilinear_interpolator RGBX8888 arithmetic, handshake and metadata test' -Quiet)) {
        throw 'Bilinear-interpolator testbench did not report PASS.'
    }
} finally {
    Pop-Location
}

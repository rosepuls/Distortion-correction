param([string]$VivadoHome = $env:VIVADO_HOME)
$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog,$xelab,$xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Tool not found: $tool" }
}
$simDir = $PSScriptRoot
$rtl = [IO.Path]::GetFullPath((Join-Path $simDir '..\rtl\correction\procedural_pixel_reader.sv'))
$tb = Join-Path $simDir 'procedural_pixel_reader_tb.sv'
$work = Join-Path $simDir ('.work\procedural-reader-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & $xvlog --sv --work work --log xvlog.log $rtl $tb
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.procedural_pixel_reader_tb -s procedural_pixel_reader_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim procedural_pixel_reader_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed.' }
    if ((Select-String xsim.log -Pattern 'FAIL' -Quiet) -or
        -not (Select-String xsim.log -Pattern 'PASS: procedural_pixel_reader neighborhood, border and handshake test' -Quiet)) {
        throw 'Procedural-pixel-reader testbench did not report PASS.'
    }
} finally { Pop-Location }

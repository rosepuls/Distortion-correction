param([string]$VivadoHome = $env:VIVADO_HOME)
$ErrorActionPreference='Stop'
if(-not $VivadoHome){throw 'Set VIVADO_HOME or pass -VivadoHome.'}
$xvlog=Join-Path $VivadoHome 'bin\xvlog.bat'; $xelab=Join-Path $VivadoHome 'bin\xelab.bat'; $xsim=Join-Path $VivadoHome 'bin\xsim.bat'
$simDir=$PSScriptRoot
$rtl=[IO.Path]::GetFullPath((Join-Path $simDir '..\rtl\correction\demo_radial_mapper.sv'))
$tb=Join-Path $simDir 'demo_radial_mapper_tb.sv'
$work=Join-Path $simDir ('.work\demo-radial-' + [guid]::NewGuid().ToString('N').Substring(0,8)); New-Item -ItemType Directory $work -Force|Out-Null
Push-Location $work
try {
 & $xvlog --sv --work work --log xvlog.log $rtl $tb; if($LASTEXITCODE-ne 0){throw 'xvlog failed.'}
 & $xelab work.demo_radial_mapper_tb -s demo_radial_mapper_tb_sim --log xelab.log; if($LASTEXITCODE-ne 0){throw 'xelab failed.'}
 & $xsim demo_radial_mapper_tb_sim -runall --log xsim.log; if($LASTEXITCODE-ne 0){throw 'xsim failed.'}
 if((Select-String xsim.log -Pattern 'FAIL' -Quiet)-or -not(Select-String xsim.log -Pattern 'PASS: demo_radial_mapper radial arithmetic, pipeline and metadata test' -Quiet)){throw 'Demo radial mapper did not report PASS.'}
} finally {Pop-Location}

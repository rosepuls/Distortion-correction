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
$sources = @(
    [System.IO.Path]::GetFullPath((Join-Path $simDir '..\rtl\correction\identity_mapper.sv')),
    [System.IO.Path]::GetFullPath((Join-Path $simDir '..\rtl\correction\coordinate_fifo.sv')),
    [System.IO.Path]::GetFullPath((Join-Path $simDir '..\rtl\correction\identity_coordinate_pipeline.sv'))
)
$testbench = Join-Path $simDir 'identity_coordinate_pipeline_tb.sv'
$workDir = Join-Path $simDir ('.work\identity-coordinate-pipeline-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

Push-Location $workDir
try {
    & $xvlog --sv --work work --log xvlog.log @sources $testbench
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.identity_coordinate_pipeline_tb -s identity_coordinate_pipeline_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim identity_coordinate_pipeline_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed.' }
    if ((Select-String -LiteralPath xsim.log -Pattern 'FAIL' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: identity mapper and coordinate FIFO preserve 24 stalled coordinates' -Quiet)) {
        throw 'Identity coordinate pipeline testbench did not report PASS.'
    }
} finally {
    Pop-Location
}

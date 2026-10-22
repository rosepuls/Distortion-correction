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

$rtlDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\rtl\memory'))
$cases = @(
    @{
        Top = 'capture_frame_admission_tb'
        Sources = @('frame_pool_manager.v', 'capture_frame_admission.v')
        Pass = 'PASS: capture_frame_admission publish and drain test'
    },
    @{
        Top = 'capture_pixel_gate_tb'
        Sources = @('capture_pixel_gate.v')
        Pass = 'PASS: capture_pixel_gate whole-frame gating test'
    }
)

foreach ($case in $cases) {
    $workDir = Join-Path $PSScriptRoot ('.work\' + $case.Top + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    $sources = @($case.Sources | ForEach-Object { Join-Path $rtlDir $_ })
    $testbench = Join-Path $PSScriptRoot ($case.Top + '.v')
    Push-Location $workDir
    try {
        & $xvlog --work work --log xvlog.log @sources $testbench
        if ($LASTEXITCODE -ne 0) { throw "xvlog failed: $($case.Top)" }
        & $xelab ('work.' + $case.Top) -s ($case.Top + '_sim') --log xelab.log
        if ($LASTEXITCODE -ne 0) { throw "xelab failed: $($case.Top)" }
        & $xsim ($case.Top + '_sim') -runall --log xsim.log
        if ($LASTEXITCODE -ne 0) { throw "xsim failed: $($case.Top)" }
        if ((Select-String -LiteralPath xsim.log -Pattern 'FATAL_ERROR|FAIL:' -Quiet) -or
            -not (Select-String -LiteralPath xsim.log -Pattern $case.Pass -Quiet)) {
            throw "Testbench did not report PASS: $($case.Top)"
        }
    } finally {
        Pop-Location
    }
}

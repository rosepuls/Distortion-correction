param([string]$VivadoHome = $env:VIVADO_HOME)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing Vivado tool: $tool" }
}
$rtl = Join-Path $PSScriptRoot '..\rtl\memory\tile_row_ddr_adapter.sv'
$tb = Join-Path $PSScriptRoot 'tile_row_ddr_adapter_tb.sv'
$work = Join-Path $PSScriptRoot ('.work\tile-row-ddr-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & $xvlog --sv --work work --log xvlog.log $rtl $tb
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.tile_row_ddr_adapter_tb -s tile_row_ddr_adapter_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim tile_row_ddr_adapter_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        (Select-String -LiteralPath xsim.log -Pattern 'FAIL' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: tile row DDR address, reservation, buffering and fault test' -Quiet)) {
        throw 'Tile-row adapter test did not report PASS.'
    }
} finally { Pop-Location }

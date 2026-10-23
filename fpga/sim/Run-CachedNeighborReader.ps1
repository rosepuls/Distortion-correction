param([string]$VivadoHome = $env:VIVADO_HOME)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) { throw 'Set VIVADO_HOME or pass -VivadoHome.' }
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing Vivado tool: $tool" }
}
$rtl = Join-Path $PSScriptRoot '..\rtl\memory'
$sources = @(
    (Join-Path $rtl 'tile_cache_bank_ram.sv'),
    (Join-Path $rtl 'pixel_tile_cache.sv'),
    (Join-Path $rtl 'tile_row_ddr_adapter.sv'),
    (Join-Path $rtl 'cached_neighbor_reader.sv'),
    (Join-Path $PSScriptRoot 'cached_neighbor_reader_tb.sv')
)
$work = Join-Path $PSScriptRoot ('.work\cached-neighbor-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & $xvlog --sv --work work --log xvlog.log @sources
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed.' }
    & $xelab work.cached_neighbor_reader_tb -s cached_neighbor_reader_tb_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed.' }
    & $xsim cached_neighbor_reader_tb_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        (Select-String -LiteralPath xsim.log -Pattern 'FAIL' -Quiet) -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: DDR Tile Cache neighbors, border, metadata and frame invalidation' -Quiet)) {
        throw 'Cached-neighbor reader test did not report PASS.'
    }
} finally { Pop-Location }

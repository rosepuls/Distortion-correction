param([string]$VivadoHome = 'D:\Xilinx\Vivado\2020.2')

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$rtl = Join-Path $projectRoot 'source\rtl\memory'
$sources = @(
    (Join-Path $rtl 'tile_cache_bank_ram.sv'),
    (Join-Path $rtl 'pixel_tile_cache.sv'),
    (Join-Path $rtl 'tile_row_ddr_adapter.sv'),
    (Join-Path $rtl 'cached_neighbor_reader.sv'),
    (Join-Path $PSScriptRoot 'stage7_tile_fill_tb.sv')
)
$work = Join-Path $PSScriptRoot '.work\tile-fill'
New-Item -ItemType Directory -Path $work -Force | Out-Null
Push-Location $work
try {
    & (Join-Path $VivadoHome 'bin\xvlog.bat') --sv --work work --log xvlog.log @sources
    if ($LASTEXITCODE -ne 0) { throw 'Stage7 tile fill xvlog failed.' }
    & (Join-Path $VivadoHome 'bin\xelab.bat') work.stage7_tile_fill_tb -s stage7_tile_fill_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'Stage7 tile fill xelab failed.' }
    & (Join-Path $VivadoHome 'bin\xsim.bat') stage7_tile_fill_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: one tile refill' -Quiet)) {
        throw 'Stage7 tile fill simulation failed.'
    }
} finally {
    Pop-Location
}

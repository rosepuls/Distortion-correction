param([string]$VivadoHome = $env:VIVADO_HOME)

$ErrorActionPreference = 'Stop'
if (-not $VivadoHome) {
    throw 'Set VIVADO_HOME or pass -VivadoHome to locate Vivado Simulator.'
}

$simDir = $PSScriptRoot
$projectRoot = Split-Path $simDir -Parent
$rtlRoot = Join-Path $projectRoot 'source\rtl'
$xvlog = Join-Path $VivadoHome 'bin\xvlog.bat'
$xelab = Join-Path $VivadoHome 'bin\xelab.bat'
$xsim = Join-Path $VivadoHome 'bin\xsim.bat'
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Vivado Simulator tool not found: $tool"
    }
}

$workDir = Join-Path $simDir ('.work\stage9-bicubic-reader-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
$files = @(
    (Join-Path $rtlRoot 'memory\tile_cache_bank_ram.sv'),
    (Join-Path $rtlRoot 'memory\pixel_tile_cache.sv'),
    (Join-Path $rtlRoot 'memory\tile_row_ddr_adapter.sv'),
    (Join-Path $rtlRoot 'memory\cached_bicubic_neighbor_reader.sv'),
    (Join-Path $simDir 'cached_bicubic_neighbor_reader_tb.sv')
)

Push-Location $workDir
try {
    & $xvlog --sv --work work --log xvlog.log $files
    if ($LASTEXITCODE -ne 0) { throw 'Stage 9 reader xvlog failed.' }
    & $xelab work.cached_bicubic_neighbor_reader_tb -s stage9_bicubic_reader_sim --log xelab.log
    if ($LASTEXITCODE -ne 0) { throw 'Stage 9 reader xelab failed.' }
    & $xsim stage9_bicubic_reader_sim -runall --log xsim.log
    if ($LASTEXITCODE -ne 0 -or
        -not (Select-String -LiteralPath xsim.log -Pattern 'PASS: Stage 9 cached 4x4 neighbor gather across tile boundaries' -Quiet)) {
        throw 'Stage 9 reader simulation did not report PASS.'
    }
} finally {
    Pop-Location
}

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$topPath = Join-Path $projectRoot 'rtl/board/pg2l200h/pg2l200h_board_top.sv'
$fdcPaths = @(
    (Join-Path $projectRoot 'boards/pg2l200h/constraints/pg2l200h_board_top.fdc'),
    (Join-Path $projectRoot 'boards/pg2l200h/pds/pg2l200h_rtl_synth/source/constraints/pg2l200h_board_top.fdc')
)

foreach ($path in @($topPath) + $fdcPaths) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing PG2L200H CDC asset: $path"
    }
}

$topText = Get-Content -LiteralPath $topPath -Raw

foreach ($register in @('capture_pix_1', 'capture_pix_2', 'display_pix_1', 'display_pix_2')) {
    if ($topText -notmatch ("reg\s+" + [regex]::Escape($register) + '\s*/\*\s*synthesis\s+syn_preserve\s*=\s*1\s*\*/')) {
        throw "CDC synchronizer register is not preserved: $register"
    }
}

foreach ($fdcPath in $fdcPaths) {
    $activeFdc = Get-Content -LiteralPath $fdcPath | Where-Object { $_ -notmatch '^\s*#' }
    $fdcText = $activeFdc -join "`n"
    foreach ($clock in @('cfg_clk', 'video_pixel_clk', 'pixclk_in')) {
        $constraint = "set_clock_groups -name $clock -asynchronous -group [get_clocks {$clock}]"
        if ($fdcText -notmatch [regex]::Escape($constraint)) {
            throw "Missing asynchronous CDC clock-group constraint in ${fdcPath}: $clock"
        }
        if ($clock -eq 'pixclk_in') {
            $clockDefinition = 'create_clock -name {pixclk_in} [get_ports {pixclk_in}]'
            if ($fdcText.IndexOf($constraint) -lt $fdcText.IndexOf($clockDefinition)) {
                throw "pixclk_in asynchronous clock group precedes its create_clock in ${fdcPath}"
            }
        }
    }
}

Write-Output 'PASS: PG2L200H CDC synchronizers are preserved and all independent clocks are asynchronous.'

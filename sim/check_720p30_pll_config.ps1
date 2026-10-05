param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

$idf = Join-Path $ProjectRoot 'ip/pango/mes50hp_video_pll/pll.idf'
$pll = Join-Path $ProjectRoot 'ip/pango/mes50hp_video_pll/pll.v'
$fdc = Join-Path $ProjectRoot 'boards/pgl50h/constraints/pgl50h_board_top.fdc'

function Require-Match {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Name
    )

    if ($Text -notmatch $Pattern) {
        throw "FAIL: $Name"
    }
}

$idfText = Get-Content $idf -Raw
$pllText = Get-Content $pll -Raw
$fdcText = Get-Content $fdc -Raw

Require-Match $idfText '<name>CLKOUT0_REQ_FREQ_basicPage</name>\s*<value>37\.1250</value>' 'PLL IDF clkout0 target is not 37.125 MHz'
Require-Match $pllText 'STATIC_RATIO0\s*=\s*22' 'generated PLL output divider is not 22'
Require-Match $pllText 'STATIC_DUTY0\s*=\s*22' 'generated PLL clkout0 duty divider is not 22'
Require-Match $fdcText '-multiply_by\s+\{49\}\s+-divide_by\s+\{66\}' 'video_pixel_clk FDC ratio does not match 50 MHz * 49 / 66'
Require-Match $fdcText '-multiply_by\s+\{49\}\s+-divide_by\s+\{246\}' 'cfg_clk FDC ratio does not match 50 MHz * 49 / 246'

Write-Output 'PASS: 720p30 PLL configuration is internally consistent'

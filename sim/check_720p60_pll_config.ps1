param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
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

Require-Match $idfText '<name>CLKOUT0_REQ_FREQ_basicPage</name>\s*<value>74\.2500</value>' 'PLL IDF clkout0 target is not 74.25 MHz'
Require-Match $pllText 'STATIC_RATIO0\s*=\s*11' 'generated PLL output divider is not 11'
Require-Match $pllText 'STATIC_DUTY0\s*=\s*11' 'generated PLL clkout0 duty divider is not 11'
Require-Match $fdcText '-multiply_by\s+\{49\}\s+-divide_by\s+\{33\}' 'video_pixel_clk FDC ratio does not match 50 MHz * 49 / 33'
Require-Match $fdcText '-multiply_by\s+\{49\}\s+-divide_by\s+\{246\}' 'cfg_clk FDC ratio does not match 50 MHz * 49 / 246'
Require-Match $fdcText 'create_clock\s+-name\s+\{pixclk_in\}.*-period\s+\{26\.936\}' 'pixclk_in must remain constrained as 37.125 MHz input'

Write-Output 'PASS: 720p60 PLL configuration is internally consistent'

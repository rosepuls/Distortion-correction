param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$idf = Join-Path $ProjectRoot 'ip/pango/pg2l200h/video_pll/pll.idf'
$pll = Join-Path $ProjectRoot 'ip/pango/pg2l200h/video_pll/pll.v'
$fdc = Join-Path $ProjectRoot 'boards/pg2l200h/constraints/pg2l200h_board_top.fdc'

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

Require-Match $idfText '<name>CLKOUT0_REQ_FREQ_basicPage</name>\s*<value>74\.25000000</value>' 'PLL IDF clkout0 target is not 74.25 MHz'
Require-Match $pllText 'CLKIN_FREQ\s*=\s*27\.0' 'PLL input must be the 27 MHz board system clock'
Require-Match $pllText 'STATIC_RATIO0\s*=\s*14\.0' 'generated PLL output divider is not 14'
Require-Match $pllText 'STATIC_DUTY0\s*=\s*14' 'generated PLL clkout0 duty divider is not 14'
Require-Match $fdcText 'create_clock\s+-name\s+\{sys_clk\}.*-period\s+\{37\.000\}' 'sys_clk must remain constrained as 27 MHz input'
Require-Match $fdcText 'create_clock\s+-name\s+\{pixclk_in\}.*-period\s+\{13\.468\}' 'pixclk_in must be constrained as 74.25 MHz 720p60 input'

Write-Output 'PASS: 720p60 PLL configuration is internally consistent'

param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage2_ddr3_720p60_rgbx8888')
)

$ErrorActionPreference = 'Stop'
$projectDir = [System.IO.Path]::GetFullPath($ProjectDirectory)
if (Test-Path -LiteralPath $projectDir) {
    throw "Existing local project will not be overwritten: $projectDir"
}
& (Join-Path $PSScriptRoot 'New-Stage2FrameSlotProject.ps1') -ProjectDirectory $projectDir

$encoding = [System.Text.Encoding]::GetEncoding('iso-8859-1')
function Replace-One {
    param([string]$File, [string]$Pattern, [string]$Replacement)
    $source = $encoding.GetString([System.IO.File]::ReadAllBytes($File))
    $matches = [regex]::Matches($source, $Pattern)
    if ($matches.Count -ne 1) {
        throw "Expected one match, found $($matches.Count): $Pattern in $File"
    }
    [System.IO.File]::WriteAllBytes($File, $encoding.GetBytes(
        [regex]::Replace($source, $Pattern, $Replacement)))
}

$rtl = Join-Path $projectDir 'source\rtl'
$frame = Join-Path $rtl 'fram_buf.v'
$top = Join-Path $rtl 'HDMI_IN_DDR3_HDMI_OUT_top.v'
$reader = Join-Path $rtl 'rd_buf.v'

Replace-One $frame '(parameter\s+PIX_WIDTH\s*=\s*)16' '${1}32'
Replace-One $top 'wire\s*\[15:0\]\s+o_rgb565\s*;' 'wire [31:0] o_rgbx;'
Replace-One $top 'wire\s*\[15:0\]\s+hdmi_data_in\s*;' 'wire [31:0] hdmi_data_in;'
Replace-One $top 'assign\s+hdmi_data_in\s*=\s*\{r_in\[7:3\],g_in\[7:2\],b_in\[7:3\]\};' "assign hdmi_data_in = {r_in,g_in,b_in,8'h00};"
Replace-One $top '\.vout_data\s*\(\s*o_rgb565\s*\)' '.vout_data      (  o_rgbx             )'
Replace-One $top 'r_out\s*<=\s*\{o_rgb565\[15:11\],3''d0\}\s*;' 'r_out        <=  o_rgbx[31:24];'
Replace-One $top 'g_out\s*<=\s*\{o_rgb565\[10:5\],2''d0\}\s*;' 'g_out        <=  o_rgbx[23:16];'
Replace-One $top 'b_out\s*<=\s*\{o_rgb565\[4:0\],3''d0\}\s*;' 'b_out        <=  o_rgbx[15:8];'

# For 32-bit pixels the generic reader path needs the same active-data delay
# as the packed paths, otherwise the first blanking word can leak into video.
Replace-One $reader '(?s)(    else\s*begin\s*assign read_en = rd_en;\s*always @\(posedge vout_clk\)\s*begin\s*)read_data <= rd_data;(\s*end\s*end\s*endgenerate)' @'
${1}if (rd_en_1d)
                read_data <= rd_data;
            else
                read_data <= {PIX_WIDTH{1'b0}};${2}
'@

Write-Host "Created RGBX8888 PDS project: $(Join-Path $projectDir 'HDMI_IN_DDR3_HDMI_OUT.pds')"

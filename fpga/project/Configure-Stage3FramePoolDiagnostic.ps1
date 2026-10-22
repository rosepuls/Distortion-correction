param(
    [string]$ProjectDirectory = (Join-Path $PSScriptRoot 'stage3_frame_pool_diagnostic')
)

$ErrorActionPreference = 'Stop'
$projectDirectory = [System.IO.Path]::GetFullPath($ProjectDirectory)
if ((Split-Path -Leaf $projectDirectory) -ne 'stage3_frame_pool_diagnostic') {
    throw 'This diagnostic edit is restricted to stage3_frame_pool_diagnostic.'
}
$framPath = Join-Path $projectDirectory 'source\rtl\fram_buf.v'
if (-not (Test-Path -LiteralPath $framPath -PathType Leaf)) {
    throw "Diagnostic fram_buf.v not found: $framPath"
}
$latin1 = [System.Text.Encoding]::GetEncoding('iso-8859-1')
$fram = $latin1.GetString([System.IO.File]::ReadAllBytes($framPath))
if ($fram.Contains('raw_de_seen') -or $fram.Contains('display_seen')) {
    throw 'Diagnostic LED instrumentation is already present.'
}

$declAnchor = '    reg seen_output_vsync;'
$declReplacement = @'
    reg seen_output_vsync;
    // Sticky milestones exposed on LED4..LED7, from least to most advanced.
    reg raw_de_seen, gated_pixel_seen;
    reg publish_seen, display_seen;
'@
$declReplacement = $declReplacement.Replace("`n", "`r`n")
if ($fram.Split([string[]]@($declAnchor), [System.StringSplitOptions]::None).Count -ne 2) {
    throw 'Expected exactly one diagnostic declaration anchor.'
}
$fram = $fram.Replace($declAnchor, $declReplacement)

$ledStart = '    assign frame_error_led = {'
$ledEnd = '    wr_buf #('
$startAt = $fram.IndexOf($ledStart, [System.StringComparison]::Ordinal)
$endAt = $fram.IndexOf($ledEnd, $startAt, [System.StringComparison]::Ordinal)
if ($startAt -lt 0 -or $endAt -lt 0 -or
    $fram.IndexOf($ledStart, $startAt + $ledStart.Length, [System.StringComparison]::Ordinal) -ge 0) {
    throw 'Could not locate the unique diagnostic LED assignment block.'
}
$debugBlock = @'
    always @(posedge vin_clk or negedge ddr_rstn) begin
        if (!ddr_rstn) begin
            raw_de_seen <= 1'b0;
            gated_pixel_seen <= 1'b0;
        end else begin
            if (wr_en)
                raw_de_seen <= 1'b1;
            if (gated_wr_en)
                gated_pixel_seen <= 1'b1;
        end
    end

    always @(posedge ddr_clk or negedge ddr_rstn) begin
        if (!ddr_rstn) begin
            publish_seen <= 1'b0;
            display_seen <= 1'b0;
        end else begin
            if (capture_publish)
                publish_seen <= 1'b1;
            if (display_valid)
                display_seen <= 1'b1;
        end
    end

    // Physical LED4..LED7 map to frame_error_led[0..3] at A17, A18, C17, B17.
    assign frame_error_led = {display_seen, publish_seen,
                              gated_pixel_seen, raw_de_seen};

'@
$debugBlock = $debugBlock.Replace("`n", "`r`n")
$fram = $fram.Substring(0, $startAt) + $debugBlock + $fram.Substring($endAt)
$latin1Bytes = $latin1.GetBytes($fram)
[System.IO.File]::WriteAllBytes($framPath, $latin1Bytes)

$readmePath = Join-Path $projectDirectory 'README.md'
$readme = @'
# Stage 3 frame-pool diagnostic project

This isolated PDS project was generated from the Stage 2 RGBX8888 inputs and
then integrated with the Stage 3 capture-to-display RTL. Stage 2 and the
original Stage 3 project are separate and are not modified by this script.

The four added diagnostic LEDs latch these milestones after DDR reset:

| LED | Meaning |
| --- | --- |
| LED4 | Raw HDMI input DE has occurred |
| LED5 | At least one pixel passed `capture_pixel_gate` into `wr_buf` |
| LED6 | At least one complete frame was published by the capture pool |
| LED7 | The display consumer took a frame and `display_valid` became true |

Interpret the LEDs cumulatively. LED4 on and LED5 off points to input polarity
or capture gating. LED5 on with LED6 off points to frame completeness or DDR
write drain. LED6 on with LED7 off points to output VS/frame-take scheduling.
All four on with a black image points to DDR readback, slot addressing, or
pixel output formatting. These are sticky milestones, so reset the board before
each observation. LED0..LED3 retain their existing heartbeat and initialization
meanings.

Build only in this directory. The bitstream is written to
`generate_bitstream/HDMI_IN_DDR3_HDMI_OUT_top.sbit`.
'@
[System.IO.File]::WriteAllText($readmePath, $readme, [System.Text.UTF8Encoding]::new($false))
Write-Host "Configured isolated Stage 3 milestone diagnostics: $projectDirectory"
